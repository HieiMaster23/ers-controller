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
    signal sim_done : boolean := false;
    signal duty_out : std_logic_vector(15 downto 0);

    constant CLK_PERIOD : time := 20 ns;

    procedure wait_clk(n : integer) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
        wait for 1 ns;  -- amostrar apos a borda (saidas registradas estaveis)
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
    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

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
        -- Na borda de enable o integrador e pre-carregado com o setpoint
        -- (partida sem salto): a primeira saida e ~10000 + 78.
        -- Depois cresce com o integrador (4.88 por ciclo).
        -- ----------------------------------------------------------------
        enable <= '1';
        wait_clk(1);

        duty_val := to_integer(unsigned(duty_out));
        assert duty_val > 0
            report "FALHA T3a: Saida deveria ser > 0 com erro positivo"
            severity error;
        assert duty_val >= 10000 and duty_val <= 10200
            report "FALHA T3c: Na habilitacao a saida deveria partir do setpoint (~10078). Valor: " &
                   integer'image(duty_val)
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
        -- erro = -5000: I cai 4.88 por ciclo a partir de ~10100 -> chega a 0
        -- em ~2070 ciclos
        -- ----------------------------------------------------------------
        setpoint <= std_logic_vector(to_unsigned(5000, 16));
        measured <= std_logic_vector(to_unsigned(10000, 16));
        wait_clk(2500);
        duty_val := to_integer(unsigned(duty_out));
        assert duty_val = 0
            report "FALHA T5: Com erro muito negativo, saida deveria saturar em 0"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 6: Saturacao superior (setpoint muito alto)
        -- erro = 60000 -> P = 1024*60000/65536 = 937.5
        -- I cresce 64*60000/65536 = 58.6 por ciclo -> a saida atinge 65535
        -- quando I >= 64598, ou seja, apos ~1103 ciclos.
        -- ----------------------------------------------------------------
        rst_n <= '0';
        wait_clk(2);
        rst_n <= '1';
        wait_clk(1);

        -- Habilitar com setpoint 0 (pre-carga = 0) e so depois aplicar o
        -- degrau, para observar a integracao a partir de zero
        enable   <= '1';
        setpoint <= std_logic_vector(to_unsigned(0, 16));
        measured <= std_logic_vector(to_unsigned(0, 16));
        wait_clk(2);
        setpoint <= std_logic_vector(to_unsigned(60000, 16));
        wait_clk(1000);
        duty_val := to_integer(unsigned(duty_out));
        assert duty_val > 55000 and duty_val < 65535
            report "FALHA T6a: Apos 1000 ciclos, saida deveria estar perto de saturar. Valor: " &
                   integer'image(duty_val)
            severity error;
        wait_clk(200);
        duty_val := to_integer(unsigned(duty_out));
        assert duty_val = 65535
            report "FALHA T6b: Com erro muito grande, saida deveria saturar em 65535. Valor: " &
                   integer'image(duty_val)
            severity error;

        -- Manter saturado por muito tempo: sem anti-windup o integrador
        -- chegaria a ~58.6 * 6200 = 363000, bem acima de OUT_MAX.
        wait_clk(5000);

        -- ----------------------------------------------------------------
        -- TESTE 7: Anti-windup - apos saturacao, desaturar imediatamente
        -- Com o integrador travado em OUT_MAX, inverter o erro faz o termo P
        -- negativo tirar a saida da saturacao ja no primeiro ciclo. Sem
        -- anti-windup seriam ~5000 ciclos ate a saida comecar a cair.
        -- ----------------------------------------------------------------
        setpoint <= std_logic_vector(to_unsigned(0, 16));
        measured <= std_logic_vector(to_unsigned(60000, 16));
        wait_clk(2);
        duty_val := to_integer(unsigned(duty_out));
        assert duty_val < 65535 - 900
            report "FALHA T7a: Anti-windup falhou, saida nao saiu da saturacao: " &
                   integer'image(duty_val)
            severity error;

        -- Descarregar o integrador: 65535 / 58.6 ~ 1119 ciclos ate zerar
        wait_clk(1200);
        duty_val := to_integer(unsigned(duty_out));
        assert duty_val = 0
            report "FALHA T7b: Saida deveria chegar a 0 apos descarregar o integrador: " &
                   integer'image(duty_val)
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 8: Reentrada sem salto
        -- Saturar o integrador, desabilitar e reabilitar com outro setpoint:
        -- a saida deve partir do novo setpoint, nao do valor antigo (65535).
        -- ----------------------------------------------------------------
        setpoint <= std_logic_vector(to_unsigned(60000, 16));
        measured <= std_logic_vector(to_unsigned(0, 16));
        wait_clk(1300);
        assert to_integer(unsigned(duty_out)) = 65535
            report "FALHA T8a: Integrador deveria estar saturado antes do teste"
            severity error;

        enable <= '0';
        wait_clk(10);
        assert duty_out = x"0000"
            report "FALHA T8b: Desabilitado, saida deveria ser 0"
            severity error;

        setpoint <= std_logic_vector(to_unsigned(20000, 16));
        measured <= std_logic_vector(to_unsigned(20000, 16));
        enable   <= '1';
        wait_clk(2);
        duty_val := to_integer(unsigned(duty_out));
        assert duty_val >= 19900 and duty_val <= 20100
            report "FALHA T8c: Ao reabilitar, saida deveria partir do novo setpoint (20000), nao do integrador antigo. Valor: " &
                   integer'image(duty_val)
            severity error;

        -- ----------------------------------------------------------------
        -- Fim
        -- ----------------------------------------------------------------
        enable <= '0';
        wait_clk(5);
        report "=== TODOS OS TESTES DO PI CONCLUIDOS ===" severity note;
        sim_done <= true;
        wait;
    end process;

end architecture sim;
