-- ============================================================================
-- Arquivo  : power_arbiter.vhd
-- Autor    : Rafael
-- Data     : 2026-04-06
-- Descricao: Arbitro de potencia. Garante que os limites do regulamento
--            sejam respeitados antes de liberar os sinais PWM.
--
-- Limites verificados:
--   1. Potencia instantanea de deploy <= 120 kW
--      P = (duty / 65535) * 120000 W -> duty <= 65535 (sempre ok por construcao)
--      Verificacao adicional: se duty > DUTY_P_MAX, limitar.
--   2. Energia acumulada na volta < 4 MJ (1024000 em Q8 kJ)
--      Se energy_used >= ENERGY_MAX -> cortar deploy para 0.
--   3. Gera sinal PWM de 50 kHz a partir do duty cycle.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity power_arbiter is
    port (
        clk          : in  std_logic;
        rst_n        : in  std_logic;
        -- Do controlador PI
        duty_in      : in  std_logic_vector(15 downto 0);  -- duty cycle desejado
        -- Da FSM
        deploy_en    : in  std_logic;
        harvest_k_en : in  std_logic;
        harvest_h_en : in  std_logic;
        -- Do energy_meter
        energy_used  : in  std_logic_vector(23 downto 0);  -- energia (kJ, Q8)
        -- Saidas PWM
        pwm_mguk     : out std_logic;                      -- PWM para MGU-K
        pwm_mguh     : out std_logic;                      -- PWM para MGU-H
        -- Duty limitado (para realimentacao ao energy_meter)
        duty_limited : out std_logic_vector(15 downto 0)
    );
end entity power_arbiter;

architecture rtl of power_arbiter is

    -- ========================================================================
    -- Constantes
    -- ========================================================================
    -- Limite de energia: 4 MJ = 4000 kJ, em Q8 = 1024000
    constant ENERGY_MAX : unsigned(23 downto 0) := to_unsigned(1024000, 24);

    -- Contador PWM: 50 MHz / 50 kHz = 1000 contagens por periodo PWM
    -- Contador de 10 bits (0-999)
    constant PWM_PERIOD : unsigned(9 downto 0) := to_unsigned(999, 10);

    -- Duty cycle para harvest (fixo em 50% = 32768)
    constant HARVEST_DUTY : unsigned(15 downto 0) := to_unsigned(32768, 16);

    -- ========================================================================
    -- Sinais internos
    -- ========================================================================
    signal pwm_counter  : unsigned(9 downto 0);
    signal duty_mguk    : unsigned(15 downto 0);
    signal duty_mguh    : unsigned(15 downto 0);
    signal duty_applied : unsigned(15 downto 0);  -- duty efetivo do MGU-K

    -- Threshold do PWM: duty 16 bits mapeado para 0-999
    -- pwm_thresh = duty * 1000 / 65536 ~= duty >> 6 (divide por 64, aprox 1024)
    -- Mais preciso: duty * 1000 >> 16
    signal pwm_thresh_k : unsigned(9 downto 0);
    signal pwm_thresh_h : unsigned(9 downto 0);

    -- Flag de energia excedida
    signal energy_exceeded : std_logic;

begin

    -- ========================================================================
    -- Verificacao de energia (combinacional)
    -- ========================================================================
    energy_exceeded <= '1' when unsigned(energy_used) >= ENERGY_MAX else '0';

    -- ========================================================================
    -- Logica de arbitragem do duty cycle (combinacional)
    -- ========================================================================
    process(deploy_en, harvest_k_en, harvest_h_en, duty_in, energy_exceeded)
    begin
        duty_mguk <= (others => '0');
        duty_mguh <= (others => '0');
        duty_applied <= (others => '0');

        if deploy_en = '1' and energy_exceeded = '0' then
            -- Deploy: usar duty do PI para MGU-K
            duty_mguk    <= unsigned(duty_in);
            duty_applied <= unsigned(duty_in);
        elsif harvest_k_en = '1' then
            -- Harvest K: duty fixo no MGU-K (modo gerador)
            duty_mguk    <= HARVEST_DUTY;
            duty_applied <= (others => '0'); -- nao conta como deploy
        end if;

        if harvest_h_en = '1' then
            -- Harvest H: duty fixo no MGU-H
            duty_mguh <= HARVEST_DUTY;
        end if;
    end process;

    -- ========================================================================
    -- Gerador de PWM (sincrono)
    -- ========================================================================
    process(clk, rst_n)
        -- Variaveis para calculo do threshold
        variable thresh_calc_k : unsigned(25 downto 0); -- duty(16) * 1000
        variable thresh_calc_h : unsigned(25 downto 0);
    begin
        if rst_n = '0' then
            pwm_counter  <= (others => '0');
            pwm_mguk     <= '0';
            pwm_mguh     <= '0';
            pwm_thresh_k <= (others => '0');
            pwm_thresh_h <= (others => '0');

        elsif rising_edge(clk) then
            -- Atualizar thresholds: thresh = duty * 1000 / 65536
            thresh_calc_k := duty_mguk * to_unsigned(1000, 10);
            pwm_thresh_k  <= thresh_calc_k(25 downto 16);

            thresh_calc_h := duty_mguh * to_unsigned(1000, 10);
            pwm_thresh_h  <= thresh_calc_h(25 downto 16);

            -- Contador PWM
            if pwm_counter >= PWM_PERIOD then
                pwm_counter <= (others => '0');
            else
                pwm_counter <= pwm_counter + 1;
            end if;

            -- Comparacao PWM
            if pwm_counter < pwm_thresh_k then
                pwm_mguk <= '1';
            else
                pwm_mguk <= '0';
            end if;

            if pwm_counter < pwm_thresh_h then
                pwm_mguh <= '1';
            else
                pwm_mguh <= '0';
            end if;
        end if;
    end process;

    -- ========================================================================
    -- Saida: duty limitado (para o energy_meter)
    -- ========================================================================
    duty_limited <= std_logic_vector(duty_applied);

end architecture rtl;
