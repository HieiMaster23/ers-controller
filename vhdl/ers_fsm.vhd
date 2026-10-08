-- ============================================================================
-- Arquivo  : ers_fsm.vhd
-- Autor    : Rafael
-- Data     : 2026-04-06
-- Descricao: Maquina de estados principal do controlador ERS.
--            Decide o modo de operacao (STANDBY, HARVESTING_K, HARVESTING_H,
--            DEPLOYING, FAULT) com base nos sinais da planta.
--
-- Histerese de SoC (evita oscilar entre deploy e harvest no limite):
--   deploy  : bloqueado quando SoC <= 25%, liberado de novo so com SoC >= 30%
--   harvest : bloqueado quando SoC >= 90%, liberado de novo so com SoC <= 85%
--   Entre os dois limiares vale a ultima decisao (flag registrada). Apos o
--   reset as duas flags comecam bloqueadas ate o SoC passar o limiar de
--   liberacao.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ers_fsm is
    port (
        clk         : in  std_logic;                     -- 50 MHz
        rst_n       : in  std_logic;                     -- reset ativo baixo
        -- Entradas da planta
        brake_pres  : in  std_logic_vector(11 downto 0); -- 0-4095 (ADC 12 bits)
        throttle    : in  std_logic_vector(11 downto 0); -- 0-4095 (ADC 12 bits)
        soc_in      : in  std_logic_vector(11 downto 0); -- 0-4095 (0-100%)
        turbo_rpm   : in  std_logic_vector(15 downto 0); -- 0-65535 RPM
        energy_used : in  std_logic_vector(23 downto 0); -- energia deployada (kJ, Q16)
        -- Saidas de habilitacao
        harvest_k_en : out std_logic;                    -- habilita harvest MGU-K
        harvest_h_en : out std_logic;                    -- habilita harvest MGU-H
        deploy_en    : out std_logic;                    -- habilita deploy
        fault_active : out std_logic;                    -- sistema em fault
        ers_mode     : out std_logic_vector(2 downto 0)  -- codigo do estado atual
    );
end entity ers_fsm;

architecture rtl of ers_fsm is

    -- ========================================================================
    -- Definicao dos estados
    -- ========================================================================
    type state_t is (STANDBY, HARVESTING_K, HARVESTING_H, DEPLOYING, FAULT);
    signal state_reg  : state_t;
    signal state_next : state_t;

    -- ========================================================================
    -- Thresholds do regulamento (constantes)
    -- ========================================================================
    -- brake_pres > 512 => frenagem significativa
    constant BRAKE_THRESH   : unsigned(11 downto 0) := to_unsigned(512, 12);
    -- throttle > 2048 => aceleracao significativa (50%)
    constant THROTTLE_THRESH: unsigned(11 downto 0) := to_unsigned(2048, 12);
    -- soc < 90% (0.90 * 4095 = 3685) => pode fazer harvest
    constant SOC_HARVEST_MAX: unsigned(11 downto 0) := to_unsigned(3685, 12);
    -- harvest volta a ser permitido com soc <= 85% (0.85 * 4095 = 3481)
    constant SOC_HARVEST_RESUME : unsigned(11 downto 0) := to_unsigned(3481, 12);
    -- soc > 25% (0.25 * 4095 = 1024) => pode fazer deploy
    constant SOC_DEPLOY_MIN : unsigned(11 downto 0) := to_unsigned(1024, 12);
    -- deploy volta a ser permitido com soc >= 30% (0.30 * 4095 = 1229)
    constant SOC_DEPLOY_RESUME  : unsigned(11 downto 0) := to_unsigned(1229, 12);
    -- soc < 20% (0.20 * 4095 = 819) => FAULT low
    constant SOC_FAULT_LOW  : unsigned(11 downto 0) := to_unsigned(819, 12);
    -- soc > 95% (0.95 * 4095 = 3890) => FAULT high
    constant SOC_FAULT_HIGH : unsigned(11 downto 0) := to_unsigned(3890, 12);
    -- turbo_rpm > 40000 => harvest H ativo
    constant TURBO_THRESH   : unsigned(15 downto 0) := to_unsigned(40000, 16);
    -- energia maxima de deploy por volta: 4 MJ = 4000 kJ
    -- Em Q16: 4000 * 65536 = 262144000 = 0x0FA00000
    -- Usando 24 bits, valor maximo representavel = 16777215
    -- Escala: energy_used em unidades de kJ com fracao Q8
    -- 4000 kJ * 256 = 1024000
    constant ENERGY_MAX     : unsigned(23 downto 0) := to_unsigned(1024000, 24);

    -- Sinais internos para comparacao
    signal brake_u   : unsigned(11 downto 0);
    signal throttle_u: unsigned(11 downto 0);
    signal soc_u     : unsigned(11 downto 0);
    signal turbo_u   : unsigned(15 downto 0);
    signal energy_u  : unsigned(23 downto 0);

    -- Histerese de SoC: flag combinacional + memoria registrada
    signal deploy_soc_ok   : std_logic;
    signal harvest_soc_ok  : std_logic;
    signal deploy_soc_reg  : std_logic;
    signal harvest_soc_reg : std_logic;

    -- Condicoes de transicao
    signal fault_cond   : std_logic;
    signal deploy_cond  : std_logic;
    signal harvest_k_cond : std_logic;
    signal harvest_h_cond : std_logic;

begin

    -- ========================================================================
    -- Conversao de entrada para unsigned
    -- ========================================================================
    brake_u    <= unsigned(brake_pres);
    throttle_u <= unsigned(throttle);
    soc_u      <= unsigned(soc_in);
    turbo_u    <= unsigned(turbo_rpm);
    energy_u   <= unsigned(energy_used);

    -- ========================================================================
    -- Avaliacao das condicoes de transicao (combinacional)
    -- ========================================================================
    fault_cond     <= '1' when (soc_u < SOC_FAULT_LOW) or
                                (soc_u > SOC_FAULT_HIGH) else '0';

    -- Histerese: bloqueio imediato no limite; liberacao so apos o limiar de
    -- retomada; entre os dois, mantem a decisao anterior (flag registrada).
    deploy_soc_ok  <= '1' when (soc_u > SOC_DEPLOY_MIN) and
                               (deploy_soc_reg = '1' or
                                soc_u >= SOC_DEPLOY_RESUME) else '0';

    harvest_soc_ok <= '1' when (soc_u < SOC_HARVEST_MAX) and
                               (harvest_soc_reg = '1' or
                                soc_u <= SOC_HARVEST_RESUME) else '0';

    deploy_cond    <= '1' when (throttle_u > THROTTLE_THRESH) and
                                (deploy_soc_ok = '1') and
                                (energy_u < ENERGY_MAX) else '0';

    harvest_k_cond <= '1' when (brake_u > BRAKE_THRESH) and
                                (harvest_soc_ok = '1') else '0';

    harvest_h_cond <= '1' when (turbo_u > TURBO_THRESH) and
                                (harvest_soc_ok = '1') else '0';

    -- ========================================================================
    -- Logica de proximo estado (combinacional)
    -- Prioridade: FAULT > DEPLOYING > HARVESTING_K > HARVESTING_H > STANDBY
    -- ========================================================================
    process(state_reg, fault_cond, deploy_cond, harvest_k_cond, harvest_h_cond)
    begin
        -- Default: manter estado atual
        state_next <= state_reg;

        -- FAULT tem prioridade maxima (qualquer estado)
        if fault_cond = '1' then
            state_next <= FAULT;
        else
            case state_reg is
                when STANDBY =>
                    if deploy_cond = '1' then
                        state_next <= DEPLOYING;
                    elsif harvest_k_cond = '1' then
                        state_next <= HARVESTING_K;
                    elsif harvest_h_cond = '1' then
                        state_next <= HARVESTING_H;
                    end if;

                when HARVESTING_K =>
                    if deploy_cond = '1' then
                        state_next <= DEPLOYING;
                    elsif harvest_k_cond = '0' then
                        if harvest_h_cond = '1' then
                            state_next <= HARVESTING_H;
                        else
                            state_next <= STANDBY;
                        end if;
                    end if;

                when HARVESTING_H =>
                    if deploy_cond = '1' then
                        state_next <= DEPLOYING;
                    elsif harvest_k_cond = '1' then
                        state_next <= HARVESTING_K;
                    elsif harvest_h_cond = '0' then
                        state_next <= STANDBY;
                    end if;

                when DEPLOYING =>
                    if deploy_cond = '0' then
                        if harvest_k_cond = '1' then
                            state_next <= HARVESTING_K;
                        elsif harvest_h_cond = '1' then
                            state_next <= HARVESTING_H;
                        else
                            state_next <= STANDBY;
                        end if;
                    end if;

                when FAULT =>
                    -- Sai de FAULT somente quando condicao de fault desaparece
                    if fault_cond = '0' then
                        state_next <= STANDBY;
                    end if;

                when others =>
                    state_next <= STANDBY;
            end case;
        end if;
    end process;

    -- ========================================================================
    -- Registrador de estado e flags de histerese
    -- (sincrono clk, reset assincrono rst_n)
    -- ========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            state_reg       <= STANDBY;
            deploy_soc_reg  <= '0';
            harvest_soc_reg <= '0';
        elsif rising_edge(clk) then
            state_reg       <= state_next;
            deploy_soc_reg  <= deploy_soc_ok;
            harvest_soc_reg <= harvest_soc_ok;
        end if;
    end process;

    -- ========================================================================
    -- Logica de saida (combinacional, baseada no estado atual)
    -- ========================================================================
    harvest_k_en <= '1' when state_reg = HARVESTING_K else '0';
    harvest_h_en <= '1' when state_reg = HARVESTING_H else '0';
    deploy_en    <= '1' when state_reg = DEPLOYING    else '0';
    fault_active <= '1' when state_reg = FAULT        else '0';

    -- Codigo do estado para monitoramento externo
    with state_reg select
        ers_mode <= "000" when STANDBY,
                    "001" when HARVESTING_K,
                    "010" when HARVESTING_H,
                    "011" when DEPLOYING,
                    "111" when FAULT,
                    "000" when others;

end architecture rtl;
