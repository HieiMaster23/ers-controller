-- ============================================================================
-- Arquivo  : tb_ers_top.vhd
-- Autor    : Rafael
-- Data     : 2026-04-06
-- Descricao: Testbench de integracao do ers_top. Simula um cenario de corrida
--            simplificado (1 volta) e verifica as transicoes de estado,
--            geracao de PWM, e acumulacao de energia.
--
-- Escala de tempo: o DUT e instanciado com CLK_HZ = 1000, entao para o
-- energy_meter cada ciclo de clock vale 1 ms. Isso permite atingir o
-- limite de 4 MJ/volta (~33k ciclos a 120 kW) em tempo de simulacao curto.
-- A logica (FSM, PI, PWM) e a mesma; so a escala de energia muda.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ers_top is
end entity tb_ers_top;

architecture sim of tb_ers_top is

    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal speed_rpm   : std_logic_vector(15 downto 0) := (others => '0');
    signal brake_pres  : std_logic_vector(11 downto 0) := (others => '0');
    signal throttle    : std_logic_vector(11 downto 0) := (others => '0');
    signal soc_in      : std_logic_vector(11 downto 0) := (others => '0');
    signal turbo_rpm   : std_logic_vector(15 downto 0) := (others => '0');
    signal lap_reset   : std_logic := '0';
    -- Sem planta neste testbench: potencia medida fica em 0, entao o PI
    -- leva o duty ao maximo durante o deploy (pior caso para o limite de
    -- energia). A malha fechada e testada na co-simulacao (cosim/).
    signal p_mguk_meas : std_logic_vector(15 downto 0) := (others => '0');
    signal pwm_mguk    : std_logic;
    signal pwm_mguh    : std_logic;
    signal ers_mode    : std_logic_vector(2 downto 0);
    signal energy_used : std_logic_vector(23 downto 0);
    signal fault_flag  : std_logic;
    signal sim_done    : boolean := false;

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

    -- Duracao dos trechos (em ciclos de clock)
    -- 1 ms = 50000 ciclos. Usamos trechos acelerados para simulacao.
    -- 10000 ciclos = 0.2 ms (suficiente para observar transicoes)
    constant PHASE_LEN : integer := 10000;

    -- Energia maxima por volta: 4 MJ = 4000 kJ, em Q8 = 1024000
    constant ENERGY_MAX : integer := 1024000;

    procedure wait_clk(n : integer) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
        wait for 1 ns;  -- amostrar apos a borda (saidas registradas estaveis)
    end procedure;

    -- Conta transicoes de um sinal PWM durante n ciclos de clock
    procedure count_toggles(signal pwm : in std_logic; n : integer;
                            variable toggles : out integer) is
        variable last : std_logic;
        variable cnt  : integer := 0;
    begin
        last := pwm;
        for i in 1 to n loop
            wait until rising_edge(clk);
            wait for 1 ns;
            if pwm /= last then
                cnt := cnt + 1;
            end if;
            last := pwm;
        end loop;
        toggles := cnt;
    end procedure;

    function energy_of(e : std_logic_vector) return integer is
    begin
        return to_integer(unsigned(e));
    end function;

begin

    dut : entity work.ers_top
        generic map (
            CLK_HZ => 1000  -- escala de tempo comprimida (ver cabecalho)
        )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            speed_rpm   => speed_rpm,
            brake_pres  => brake_pres,
            throttle    => throttle,
            soc_in      => soc_in,
            turbo_rpm   => turbo_rpm,
            lap_reset   => lap_reset,
            p_mguk_meas => p_mguk_meas,
            pwm_mguk    => pwm_mguk,
            pwm_mguh    => pwm_mguh,
            ers_mode    => ers_mode,
            energy_used => energy_used,
            fault_flag  => fault_flag
        );

    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    stim_proc : process
        variable toggles  : integer;
        variable e_before : integer;
    begin
        -- ================================================================
        -- RESET
        -- ================================================================
        rst_n <= '0';
        wait_clk(5);
        rst_n <= '1';
        wait_clk(2);

        -- Condicoes iniciais: SoC 70%, velocidade 5000 RPM
        soc_in    <= std_logic_vector(to_unsigned(2867, 12)); -- ~70%
        speed_rpm <= std_logic_vector(to_unsigned(5000, 16));

        -- ================================================================
        -- FASE 1: STANDBY (nada ativo)
        -- ================================================================
        report "--- FASE 1: STANDBY ---" severity note;
        wait_clk(PHASE_LEN);
        assert ers_mode = "000"
            report "FALHA F1: Deveria estar em STANDBY" severity error;
        assert fault_flag = '0'
            report "FALHA F1: fault_flag deveria ser 0" severity error;

        -- ================================================================
        -- FASE 2: ACELERACAO -> DEPLOYING
        -- throttle = 3000 (>2048), SoC ok, energia ok
        -- ================================================================
        report "--- FASE 2: DEPLOYING (aceleracao) ---" severity note;
        throttle  <= std_logic_vector(to_unsigned(3000, 12));
        speed_rpm <= std_logic_vector(to_unsigned(12000, 16));
        turbo_rpm <= std_logic_vector(to_unsigned(50000, 16));
        wait_clk(5); -- esperar transicao
        assert ers_mode = "011"
            report "FALHA F2: Deveria estar em DEPLOYING" severity error;

        -- Aguardar para observar PWM e acumulacao de energia
        wait_clk(PHASE_LEN - 2000);
        count_toggles(pwm_mguk, 2000, toggles);
        assert toggles >= 2
            report "FALHA F2: pwm_mguk deveria oscilar durante deploy (transicoes = " &
                   integer'image(toggles) & ")" severity error;
        report "F2: energy_used = " & integer'image(energy_of(energy_used))
               severity note;
        -- ~10 s de deploy com duty subindo ate 100%: entre 0 e 4 MJ
        assert energy_of(energy_used) > ENERGY_MAX / 4 and
               energy_of(energy_used) < ENERGY_MAX
            report "FALHA F2: energia deveria acumular durante deploy, obtido " &
                   integer'image(energy_of(energy_used)) severity error;

        -- ================================================================
        -- FASE 3: FRENAGEM -> HARVESTING_K
        -- brake = 2000 (>512), soltar acelerador
        -- ================================================================
        report "--- FASE 3: HARVESTING_K (frenagem) ---" severity note;
        throttle   <= (others => '0');
        brake_pres <= std_logic_vector(to_unsigned(2000, 12));
        speed_rpm  <= std_logic_vector(to_unsigned(15000, 16));
        turbo_rpm  <= std_logic_vector(to_unsigned(30000, 16)); -- abaixo threshold
        wait_clk(5);
        assert ers_mode = "001"
            report "FALHA F3: Deveria estar em HARVESTING_K" severity error;
        e_before := energy_of(energy_used);
        count_toggles(pwm_mguk, 2000, toggles);
        assert toggles >= 2
            report "FALHA F3: pwm_mguk deveria oscilar em HARVESTING_K (transicoes = " &
                   integer'image(toggles) & ")" severity error;

        wait_clk(PHASE_LEN);
        assert energy_of(energy_used) = e_before
            report "FALHA F3: harvest nao deve contar como energia de deploy"
            severity error;

        -- ================================================================
        -- FASE 4: TURBO ALTO -> HARVESTING_H
        -- soltar freio, turbo > 40000
        -- ================================================================
        report "--- FASE 4: HARVESTING_H (turbo) ---" severity note;
        brake_pres <= (others => '0');
        turbo_rpm  <= std_logic_vector(to_unsigned(50000, 16));
        wait_clk(5);
        assert ers_mode = "010"
            report "FALHA F4: Deveria estar em HARVESTING_H" severity error;

        wait_clk(PHASE_LEN);

        -- ================================================================
        -- FASE 5: FAULT (SoC muito baixo)
        -- ================================================================
        report "--- FASE 5: FAULT (SoC baixo) ---" severity note;
        soc_in    <= std_logic_vector(to_unsigned(500, 12)); -- ~12%
        turbo_rpm <= (others => '0');
        wait_clk(5);
        assert ers_mode = "111"
            report "FALHA F5: Deveria estar em FAULT" severity error;
        assert fault_flag = '1'
            report "FALHA F5: fault_flag deveria ser 1" severity error;

        wait_clk(PHASE_LEN);

        -- ================================================================
        -- FASE 6: Recuperacao do FAULT
        -- ================================================================
        report "--- FASE 6: Recuperacao FAULT -> STANDBY ---" severity note;
        soc_in <= std_logic_vector(to_unsigned(2867, 12)); -- normalizar
        wait_clk(5);
        assert ers_mode = "000"
            report "FALHA F6: Deveria voltar a STANDBY" severity error;

        -- ================================================================
        -- FASE 7: LAP RESET
        -- ================================================================
        report "--- FASE 7: LAP RESET ---" severity note;
        -- Primeiro, acumular alguma energia
        throttle  <= std_logic_vector(to_unsigned(3000, 12));
        speed_rpm <= std_logic_vector(to_unsigned(10000, 16));
        wait_clk(PHASE_LEN);

        report "F7: Energia antes do reset = " &
               integer'image(energy_of(energy_used)) severity note;
        assert energy_of(energy_used) > 0
            report "FALHA F7: deveria haver energia acumulada antes do reset"
            severity error;

        -- Pulso de lap_reset
        lap_reset <= '1';
        wait_clk(1);
        lap_reset <= '0';
        wait_clk(5);

        report "F7: Energia apos reset = " &
               integer'image(energy_of(energy_used)) severity note;
        -- Deploy continua ativo: apos 5 ciclos (5 ms) no maximo ~0.6 kJ (154 Q8)
        assert energy_of(energy_used) <= 154
            report "FALHA F7: energia deveria ter zerado com lap_reset, obtido " &
                   integer'image(energy_of(energy_used)) severity error;

        -- ================================================================
        -- FASE 8: LIMITE DE 4 MJ/VOLTA
        -- Deploy continuo: a 120 kW o limite chega em ~33 s (33k ciclos).
        -- Energia deve travar em 4 MJ e a FSM deve sair de DEPLOYING.
        -- ================================================================
        report "--- FASE 8: Corte de deploy em 4 MJ ---" severity note;
        wait_clk(40000);
        assert energy_of(energy_used) = ENERGY_MAX
            report "FALHA F8: energia deveria travar em 4 MJ, obtido " &
                   integer'image(energy_of(energy_used)) severity error;
        assert ers_mode = "000"
            report "FALHA F8: com 4 MJ usados, FSM deveria sair de DEPLOYING"
            severity error;
        count_toggles(pwm_mguk, 2000, toggles);
        assert toggles = 0 and pwm_mguk = '0'
            report "FALHA F8: pwm_mguk deveria estar desligado apos o limite"
            severity error;

        -- ================================================================
        -- FASE 9: Nova volta libera deploy novamente
        -- ================================================================
        report "--- FASE 9: Nova volta ---" severity note;
        lap_reset <= '1';
        wait_clk(1);
        lap_reset <= '0';
        wait_clk(5);
        assert ers_mode = "011"
            report "FALHA F9: apos lap_reset, deploy deveria voltar" severity error;

        -- ================================================================
        -- FIM
        -- ================================================================
        throttle   <= (others => '0');
        brake_pres <= (others => '0');
        turbo_rpm  <= (others => '0');
        wait_clk(PHASE_LEN);

        report "=== TODOS OS TESTES DE INTEGRACAO CONCLUIDOS ===" severity note;
        sim_done <= true;
        wait;
    end process;

end architecture sim;
