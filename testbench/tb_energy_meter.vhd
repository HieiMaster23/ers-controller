-- ============================================================================
-- Arquivo  : tb_energy_meter.vhd
-- Autor    : Rafael
-- Data     : 2026-10-07
-- Descricao: Testbench do integrador de energia. Verifica valores numericos
--            da integracao, saturacao em 4 MJ (sem dar a volta), retencao
--            fora do deploy e reset de volta.
--
-- Usa duas instancias com as mesmas entradas:
--   dut_real : CLK_HZ = 50 MHz (escala real do projeto)
--   dut_fast : CLK_HZ = 1 kHz  (cada ciclo vale 1 ms -> 4 MJ a 120 kW em
--              ~33334 ciclos, permitindo testar o limite da volta)
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_energy_meter is
end entity tb_energy_meter;

architecture sim of tb_energy_meter is

    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal deploy_en   : std_logic := '0';
    signal duty_cycle  : std_logic_vector(15 downto 0) := (others => '0');
    signal lap_reset   : std_logic := '0';
    signal energy_real : std_logic_vector(23 downto 0);
    signal energy_fast : std_logic_vector(23 downto 0);
    signal sim_done    : boolean := false;

    constant CLK_PERIOD : time := 20 ns;
    constant ENERGY_MAX : integer := 1024000;  -- 4 MJ em kJ Q8

    -- Avanca n bordas de subida e amostra 1 ns depois (saidas estaveis)
    procedure wait_clk(n : integer) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
    end procedure;

    -- Verifica valor dentro de uma tolerancia absoluta
    procedure check_near(name : string; got, expected, tol : integer) is
    begin
        assert abs (got - expected) <= tol
            report "FALHA " & name & ": esperado " & integer'image(expected) &
                   " +/- " & integer'image(tol) & ", obtido " &
                   integer'image(got)
            severity error;
        report name & ": " & integer'image(got) &
               " (esperado " & integer'image(expected) & ")" severity note;
    end procedure;

begin

    dut_real : entity work.energy_meter
        generic map (CLK_HZ => 50_000_000, P_MAX_W => 120_000)
        port map (
            clk         => clk,
            rst_n       => rst_n,
            deploy_en   => deploy_en,
            duty_cycle  => duty_cycle,
            lap_reset   => lap_reset,
            energy_used => energy_real
        );

    dut_fast : entity work.energy_meter
        generic map (CLK_HZ => 1_000, P_MAX_W => 120_000)
        port map (
            clk         => clk,
            rst_n       => rst_n,
            deploy_en   => deploy_en,
            duty_cycle  => duty_cycle,
            lap_reset   => lap_reset,
            energy_used => energy_fast
        );

    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    stim_proc : process
        variable e_real : integer;
        variable e_fast : integer;
    begin
        -- ----------------------------------------------------------------
        -- TESTE 1: Reset -> energia zero
        -- ----------------------------------------------------------------
        rst_n <= '0';
        wait_clk(3);
        rst_n <= '1';
        wait_clk(1);
        check_near("T1 reset (fast)", to_integer(unsigned(energy_fast)), 0, 0);
        check_near("T1 reset (real)", to_integer(unsigned(energy_real)), 0, 0);

        -- ----------------------------------------------------------------
        -- TESTE 2: Deploy 100% por 30000 ciclos (fast = 30 s)
        -- E = 120 kW * 30 s = 3600 kJ -> 3600 * 256 = 921600 (Q8)
        -- ----------------------------------------------------------------
        deploy_en  <= '1';
        duty_cycle <= x"FFFF";
        wait_clk(30000);
        check_near("T2 30 s @ 120 kW (fast)",
                   to_integer(unsigned(energy_fast)), 921600, 100);

        -- ----------------------------------------------------------------
        -- TESTE 3: Continuar ate passar de 4 MJ -> satura exatamente no limite
        -- ----------------------------------------------------------------
        wait_clk(10000);
        check_near("T3 saturacao em 4 MJ (fast)",
                   to_integer(unsigned(energy_fast)), ENERGY_MAX, 0);

        -- ----------------------------------------------------------------
        -- TESTE 4: Deploy continua por 250000 ciclos no total
        --   fast: deve continuar travado em 4 MJ (sem overflow/wrap)
        --   real: 250000 ciclos = 5 ms -> 120 kW * 5 ms = 0.6 kJ = 153.6 (Q8)
        -- ----------------------------------------------------------------
        wait_clk(250_000 - 40001);
        check_near("T4 sem wrap apos saturar (fast)",
                   to_integer(unsigned(energy_fast)), ENERGY_MAX, 0);
        check_near("T4 5 ms @ 120 kW (real)",
                   to_integer(unsigned(energy_real)), 153, 1);

        -- ----------------------------------------------------------------
        -- TESTE 5: Sem deploy -> energia retida
        -- ----------------------------------------------------------------
        deploy_en <= '0';
        wait_clk(1);
        e_real := to_integer(unsigned(energy_real));
        e_fast := to_integer(unsigned(energy_fast));
        wait_clk(1000);
        check_near("T5 retencao (real)",
                   to_integer(unsigned(energy_real)), e_real, 0);
        check_near("T5 retencao (fast)",
                   to_integer(unsigned(energy_fast)), e_fast, 0);

        -- ----------------------------------------------------------------
        -- TESTE 6: Lap reset -> zera as duas instancias
        -- ----------------------------------------------------------------
        lap_reset <= '1';
        wait_clk(1);
        lap_reset <= '0';
        wait_clk(1);
        check_near("T6 lap reset (fast)", to_integer(unsigned(energy_fast)), 0, 0);
        check_near("T6 lap reset (real)", to_integer(unsigned(energy_real)), 0, 0);

        -- ----------------------------------------------------------------
        -- TESTE 7: Linearidade com duty 50% por 10000 ciclos (fast = 10 s)
        -- P = 32768/65535 * 120 kW = 60.0009 kW -> E = 600.009 kJ
        -- Q8: 600.009 * 256 = 153602
        -- ----------------------------------------------------------------
        deploy_en  <= '1';
        duty_cycle <= x"8000";
        wait_clk(10000);
        deploy_en  <= '0';
        wait_clk(1);
        check_near("T7 10 s @ 60 kW (fast)",
                   to_integer(unsigned(energy_fast)), 153602, 20);

        -- ----------------------------------------------------------------
        -- TESTE 8: Lap reset tem prioridade sobre deploy
        -- ----------------------------------------------------------------
        deploy_en <= '1';
        lap_reset <= '1';
        wait_clk(5);
        check_near("T8 lap reset com deploy ativo (fast)",
                   to_integer(unsigned(energy_fast)), 0, 0);
        lap_reset <= '0';
        deploy_en <= '0';

        report "=== TODOS OS TESTES DO ENERGY METER CONCLUIDOS ===" severity note;
        sim_done <= true;
        wait;
    end process;

end architecture sim;
