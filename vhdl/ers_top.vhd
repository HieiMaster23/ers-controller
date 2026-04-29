-- ============================================================================
-- Arquivo  : ers_top.vhd
-- Autor    : Rafael
-- Data     : 2026-04-06
-- Descricao: Entidade top-level do controlador ERS. Instancia e interconecta
--            todos os modulos: FSM, PI Controller, Power Arbiter, Energy Meter.
--            Esta e a unica entidade visivel pelo bloco HDL Cosimulation
--            do Simulink.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ers_top is
    port (
        -- Clock e reset
        clk         : in  std_logic;                     -- 50 MHz (periodo = 20 ns)
        rst_n       : in  std_logic;                     -- reset ativo em nivel baixo
        -- Entradas da planta (Simulink)
        speed_rpm   : in  std_logic_vector(15 downto 0); -- 0 a 20000 RPM, unsigned
        brake_pres  : in  std_logic_vector(11 downto 0); -- 0 a 4095 (ADC 12 bits)
        throttle    : in  std_logic_vector(11 downto 0); -- 0 a 4095 (ADC 12 bits)
        soc_in      : in  std_logic_vector(11 downto 0); -- 0 a 4095 = 0% a 100%
        turbo_rpm   : in  std_logic_vector(15 downto 0); -- 0 a 65535 RPM
        lap_reset   : in  std_logic;                     -- pulso de reset de volta
        -- Saidas para a planta (Simulink)
        pwm_mguk    : out std_logic;                     -- PWM para MGU-K (50 kHz)
        pwm_mguh    : out std_logic;                     -- PWM para MGU-H (50 kHz)
        ers_mode    : out std_logic_vector(2 downto 0);  -- modo atual da FSM
        energy_used : out std_logic_vector(23 downto 0); -- energia usada (kJ, Q8)
        fault_flag  : out std_logic                      -- flag de falha ativa
    );
end entity ers_top;

architecture structural of ers_top is

    -- ========================================================================
    -- Sinais internos de interconexao
    -- ========================================================================

    -- FSM -> outros modulos
    signal harvest_k_en_i : std_logic;
    signal harvest_h_en_i : std_logic;
    signal deploy_en_i    : std_logic;
    signal fault_active_i : std_logic;
    signal ers_mode_i     : std_logic_vector(2 downto 0);

    -- PI Controller -> Power Arbiter
    signal duty_from_pi   : std_logic_vector(15 downto 0);

    -- Power Arbiter -> Energy Meter (duty efetivo apos limitacao)
    signal duty_limited_i : std_logic_vector(15 downto 0);

    -- Energy Meter -> FSM e Power Arbiter
    signal energy_used_i  : std_logic_vector(23 downto 0);

    -- PI enable: ativo em deploy OU harvest_k
    signal pi_enable_i    : std_logic;

    -- Setpoint do PI: depende do modo
    signal pi_setpoint_i  : std_logic_vector(15 downto 0);

begin

    -- ========================================================================
    -- Logica de setpoint e enable do PI (combinacional)
    -- ========================================================================
    -- PI habilitado durante deploy (controla potencia de tracao)
    pi_enable_i <= deploy_en_i;

    -- Setpoint proporcional ao throttle durante deploy
    -- throttle (12 bits, 0-4095) -> setpoint (16 bits, 0-65535)
    -- setpoint = throttle * 16
    pi_setpoint_i <= throttle & "0000" when deploy_en_i = '1' else
                     (others => '0');

    -- ========================================================================
    -- Instancia: FSM
    -- ========================================================================
    u_fsm : entity work.ers_fsm
        port map (
            clk          => clk,
            rst_n        => rst_n,
            brake_pres   => brake_pres,
            throttle     => throttle,
            soc_in       => soc_in,
            turbo_rpm    => turbo_rpm,
            energy_used  => energy_used_i,
            harvest_k_en => harvest_k_en_i,
            harvest_h_en => harvest_h_en_i,
            deploy_en    => deploy_en_i,
            fault_active => fault_active_i,
            ers_mode     => ers_mode_i
        );

    -- ========================================================================
    -- Instancia: Controlador PI
    -- ========================================================================
    u_pi : entity work.pi_controller
        generic map (
            KP      => 1024,   -- 0.015625 em Q16
            KI      => 64,     -- 0.000977 em Q16
            OUT_MAX => 65535,
            OUT_MIN => 0
        )
        port map (
            clk      => clk,
            rst_n    => rst_n,
            enable   => pi_enable_i,
            setpoint => pi_setpoint_i,
            measured => speed_rpm,  -- feedback: velocidade como proxy de potencia
            duty_out => duty_from_pi
        );

    -- ========================================================================
    -- Instancia: Arbitro de Potencia
    -- ========================================================================
    u_arbiter : entity work.power_arbiter
        port map (
            clk          => clk,
            rst_n        => rst_n,
            duty_in      => duty_from_pi,
            deploy_en    => deploy_en_i,
            harvest_k_en => harvest_k_en_i,
            harvest_h_en => harvest_h_en_i,
            energy_used  => energy_used_i,
            pwm_mguk     => pwm_mguk,
            pwm_mguh     => pwm_mguh,
            duty_limited => duty_limited_i
        );

    -- ========================================================================
    -- Instancia: Integrador de Energia
    -- ========================================================================
    u_energy : entity work.energy_meter
        port map (
            clk         => clk,
            rst_n       => rst_n,
            deploy_en   => deploy_en_i,
            duty_cycle  => duty_limited_i,
            lap_reset   => lap_reset,
            energy_used => energy_used_i
        );

    -- ========================================================================
    -- Saidas top-level
    -- ========================================================================
    ers_mode    <= ers_mode_i;
    energy_used <= energy_used_i;
    fault_flag  <= fault_active_i;

end architecture structural;
