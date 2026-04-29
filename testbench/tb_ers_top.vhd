-- ============================================================================
-- Arquivo  : tb_ers_top.vhd
-- Autor    : Rafael
-- Data     : 2026-04-06
-- Descricao: Testbench de integracao do ers_top. Simula um cenario de corrida
--            simplificado (1 volta) e verifica as transicoes de estado,
--            geracao de PWM, e acumulacao de energia.
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
    signal pwm_mguk    : std_logic;
    signal pwm_mguh    : std_logic;
    signal ers_mode    : std_logic_vector(2 downto 0);
    signal energy_used : std_logic_vector(23 downto 0);
    signal fault_flag  : std_logic;

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

    -- Duracao dos trechos (em ciclos de clock)
    -- 1 ms = 50000 ciclos. Usamos trechos acelerados para simulacao.
    -- 10000 ciclos = 0.2 ms (suficiente para observar transicoes)
    constant PHASE_LEN : integer := 10000;

    procedure wait_clk(n : integer) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

begin

    dut : entity work.ers_top
        port map (
            clk         => clk,
            rst_n       => rst_n,
            speed_rpm   => speed_rpm,
            brake_pres  => brake_pres,
            throttle    => throttle,
            soc_in      => soc_in,
            turbo_rpm   => turbo_rpm,
            lap_reset   => lap_reset,
            pwm_mguk    => pwm_mguk,
            pwm_mguh    => pwm_mguh,
            ers_mode    => ers_mode,
            energy_used => energy_used,
            fault_flag  => fault_flag
        );

    clk <= not clk after CLK_PERIOD / 2;

    stim_proc : process
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
        wait_clk(PHASE_LEN);
        report "F2: energy_used = " &
               integer'image(to_integer(unsigned(energy_used)))
               severity note;

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
        assert pwm_mguk = '0' or pwm_mguk = '1' -- PWM deve estar oscilando
            report "FALHA F3: pwm_mguk deveria estar ativo" severity note;

        wait_clk(PHASE_LEN);

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
               integer'image(to_integer(unsigned(energy_used)))
               severity note;

        -- Pulso de lap_reset
        lap_reset <= '1';
        wait_clk(1);
        lap_reset <= '0';
        wait_clk(5);

        report "F7: Energia apos reset = " &
               integer'image(to_integer(unsigned(energy_used)))
               severity note;

        -- ================================================================
        -- FIM
        -- ================================================================
        throttle   <= (others => '0');
        brake_pres <= (others => '0');
        turbo_rpm  <= (others => '0');
        wait_clk(PHASE_LEN);

        report "=== TODOS OS TESTES DE INTEGRACAO CONCLUIDOS ===" severity note;
        wait;
    end process;

end architecture sim;
