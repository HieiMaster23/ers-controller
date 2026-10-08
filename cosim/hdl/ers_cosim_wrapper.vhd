-- ============================================================================
-- Arquivo  : ers_cosim_wrapper.vhd
-- Autor    : Rafael
-- Data     : 2026-10-08
-- Descricao: Harness de co-simulacao (somente simulacao, nao sintetizavel).
--            Envolve o ers_top real e adiciona o que a planta Python precisa:
--              - gerador de clock interno (evita um callback Python por ciclo)
--              - medidores de duty do PWM: contam ciclos em '1' a cada
--                periodo de PWM, como o filtro passa-baixa natural de um
--                motor/inversor "enxerga" o PWM
--
-- Escala de tempo da co-simulacao:
--   CLK_HZ = 5 kHz (200 us por ciclo), PWM com 100 contagens = 20 ms.
--   A planta Python avanca em passos de 20 ms = 1 periodo de PWM.
--   O controlador e o mesmo RTL; muda so a frequencia do clock. O clock
--   baixo mantem a co-simulacao rapida (o GHDL fica bem mais lento quando
--   controlado via VPI). Os ganhos do PI sao por ciclo, entao a dinamica
--   da malha depende do clock: em 50 MHz seria preciso dividir a taxa do PI.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ers_cosim_wrapper is
    generic (
        CLK_HZ     : positive := 5_000;
        PWM_PERIOD : positive := 99;      -- 100 contagens por periodo
        -- Watchdog: encerra a simulacao se o Python nao a finalizar
        MAX_TIME   : time     := 900 sec;
        KP         : integer  := 1024;
        KI         : integer  := 64
    );
    port (
        rst_n       : in  std_logic;
        -- Entradas da planta (escritas pelo Python)
        speed_rpm   : in  std_logic_vector(15 downto 0);
        brake_pres  : in  std_logic_vector(11 downto 0);
        throttle    : in  std_logic_vector(11 downto 0);
        soc_in      : in  std_logic_vector(11 downto 0);
        turbo_rpm   : in  std_logic_vector(15 downto 0);
        lap_reset   : in  std_logic;
        p_mguk_meas : in  std_logic_vector(15 downto 0);
        -- Saidas do controlador (lidas pelo Python)
        ers_mode    : out std_logic_vector(2 downto 0);
        energy_used : out std_logic_vector(23 downto 0);
        fault_flag  : out std_logic;
        -- Duty medido no ultimo periodo completo de PWM (0 a PWM_PERIOD+1)
        duty_k_cnt  : out std_logic_vector(15 downto 0);
        duty_h_cnt  : out std_logic_vector(15 downto 0)
    );
end entity ers_cosim_wrapper;

architecture sim of ers_cosim_wrapper is

    constant CLK_PERIOD : time := 1 sec / CLK_HZ;

    signal clk      : std_logic := '0';
    signal pwm_mguk : std_logic;
    signal pwm_mguh : std_logic;

begin

    clk <= not clk after CLK_PERIOD / 2;

    watchdog : process
    begin
        wait for MAX_TIME;
        report "Watchdog: co-simulacao excedeu MAX_TIME" severity failure;
        wait;
    end process;

    u_ers : entity work.ers_top
        generic map (
            CLK_HZ     => CLK_HZ,
            KP         => KP,
            KI         => KI,
            PWM_PERIOD => PWM_PERIOD
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

    -- ========================================================================
    -- Medidores de duty: janela de PWM_PERIOD+1 ciclos
    -- ========================================================================
    process(clk, rst_n)
        variable win    : natural range 0 to PWM_PERIOD := 0;
        variable high_k : natural range 0 to PWM_PERIOD + 1 := 0;
        variable high_h : natural range 0 to PWM_PERIOD + 1 := 0;
    begin
        if rst_n = '0' then
            win        := 0;
            high_k     := 0;
            high_h     := 0;
            duty_k_cnt <= (others => '0');
            duty_h_cnt <= (others => '0');
        elsif rising_edge(clk) then
            if pwm_mguk = '1' then
                high_k := high_k + 1;
            end if;
            if pwm_mguh = '1' then
                high_h := high_h + 1;
            end if;
            if win = PWM_PERIOD then
                duty_k_cnt <= std_logic_vector(to_unsigned(high_k, 16));
                duty_h_cnt <= std_logic_vector(to_unsigned(high_h, 16));
                win    := 0;
                high_k := 0;
                high_h := 0;
            else
                win := win + 1;
            end if;
        end if;
    end process;

end architecture sim;
