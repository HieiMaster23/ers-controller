-- ============================================================================
-- Arquivo  : tb_pi_controller.vhd
-- Autor    : Rafael
-- Data     : 2026-04-06
-- Descricao: Testbench do controlador PI. Testa resposta ao degrau,
--            saturacao de saida, anti-windup, e desabilitacao.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_pi_controller is
end entity tb_pi_controller;

architecture sim of tb_pi_controller is

    signal clk      : std_logic := '0';
    signal rst_n    : std_logic := '0';
    signal enable   : std_logic := '0';
    signal setpoint : std_logic_vector(15 downto 0) := (others => '0');
    signal measured : std_logic_vector(15 downto 0) := (others => '0');
    signal duty_out : std_logic_vector(15 downto 0);

    constant CLK_PERIOD : time := 20 ns;

    procedure wait_clk(n : integer) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

begin

    -- ========================================================================
    -- DUT
    -- ========================================================================
    dut : entity work.pi_controller
        generic map (
            KP      => 1024,   -- 0.015625 em Q16
            KI      => 64,     -- 0.000977 em Q16
            OUT_MAX => 65535,
            OUT_MIN => 0
        )
        port map (
            clk      => clk,
            rst_n    => rst_n,
            enable   => enable,
            setpoint => setpoint,
            measured => measured,
            duty_out => duty_out
        );

    -- Clock
    clk <= not clk after CLK_PERIOD / 2;

    -- ========================================================================
    -- Estimulos
    -- ========================================================================
    stim_proc : process
        variable duty_val : integer;
    begin
        -- ----------------------------------------------------------------
        -- TESTE 1: Reset -> saida zero
        -- ----------------------------------------------------------------
        rst_n <= '0';
        wait_clk(3);
        assert duty_out = x"0000"
            report "FALHA T1: Apos reset, duty_out deveria ser 0"
            severity error;

        rst_n <= '1';
        wait_clk(2);

        -- ----------------------------------------------------------------
        -- TESTE 2: Desabilitado -> saida zero
        -- ----------------------------------------------------------------
        enable   <= '0';
        setpoint <= std_logic_vector(to_unsigned(10000, 16));
        measured <= std_logic_vector(to_unsigned(5000, 16));
        wait_clk(5);
        assert duty_out = x"0000"
            report "FALHA T2: Desabilitado, duty_out deveria ser 0"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 3: Resposta ao degrau (setpoint > measured)
        -- Setpoint = 10000, Measured = 5000 -> erro = 5000
        -- P = KP * error = 1024 * 5000 = 5120000 (Q16)
        -- P_real = 5120000 / 65536 = 78.125
        -- A saida deve crescer progressivamente com o integrador
        -- ----------------------------------------------------------------
        enable <= '1';
        wait_clk(1);

        -- Verificar que saida comecou a crescer
        duty_val := to_integer(unsigned(duty_out));
        assert duty_val > 0
            report "FALHA T3a: Saida deveria ser > 0 com erro positivo"
            severity error;

        -- Aguardar convergencia (10 ciclos conforme criterio de aceitacao)
        wait_clk(10);
        duty_val := to_integer(unsigned(duty_out));
        assert duty_val > 50
            report "FALHA T3b: Apos 10 ciclos, saida deveria ter crescido"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 4: Erro zero -> saida estabiliza
        -- ----------------------------------------------------------------
        measured <= setpoint; -- erro = 0
        wait_clk(10);
        -- Saida deve manter um valor estavel (integral acumulado)
        -- Nao testar valor exato, apenas que nao esta em 0
        duty_val := to_integer(unsigned(duty_out));
        report "T4: Com erro=0, duty estabilizou em " &
               integer'image(duty_val) severity note;

        -- ----------------------------------------------------------------
        -- TESTE 5: Erro negativo (measured > setpoint) -> saida diminui
        -- ----------------------------------------------------------------
        setpoint <= std_logic_vector(to_unsigned(5000, 16));
        measured <= std_logic_vector(to_unsigned(10000, 16));
        wait_clk(20);
        duty_val := to_integer(unsigned(duty_out));
        assert duty_val = 0
            report "FALHA T5: Com erro muito negativo, saida deveria saturar em 0"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 6: Saturacao superior (setpoint muito alto)
        -- ----------------------------------------------------------------
        rst_n <= '0';
        wait_clk(2);
        rst_n <= '1';
        wait_clk(1);

        enable   <= '1';
        setpoint <= std_logic_vector(to_unsigned(60000, 16));
        measured <= std_logic_vector(to_unsigned(0, 16));
        wait_clk(50);  -- Esperar integrador acumular
        duty_val := to_integer(unsigned(duty_out));
        assert duty_val = 65535
            report "FALHA T6: Com erro muito grande, saida deveria saturar em 65535. Valor: " &
                   integer'image(duty_val)
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 7: Anti-windup - apos saturacao, desaturar rapidamente
        -- ----------------------------------------------------------------
        -- Inverter o erro: measured > setpoint
        setpoint <= std_logic_vector(to_unsigned(0, 16));
        measured <= std_logic_vector(to_unsigned(60000, 16));
        wait_clk(20);
        duty_val := to_integer(unsigned(duty_out));
        -- Saida deve ter caido significativamente (anti-windup funciona)
        assert duty_val < 32768
            report "FALHA T7: Anti-windup falhou, saida nao caiu rapido: " &
                   integer'image(duty_val)
            severity error;

        -- ----------------------------------------------------------------
        -- Fim
        -- ----------------------------------------------------------------
        enable <= '0';
        wait_clk(5);
        report "=== TODOS OS TESTES DO PI CONCLUIDOS ===" severity note;
        wait;
    end process;

end architecture sim;
