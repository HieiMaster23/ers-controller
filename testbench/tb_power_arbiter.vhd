-- ============================================================================
-- Arquivo  : tb_power_arbiter.vhd
-- Autor    : Rafael
-- Data     : 2026-04-06
-- Descricao: Testbench do arbitro de potencia. Testa corte por energia,
--            geracao de PWM, e modos de operacao (deploy/harvest).
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_power_arbiter is
end entity tb_power_arbiter;

architecture sim of tb_power_arbiter is

    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';
    signal duty_in      : std_logic_vector(15 downto 0) := (others => '0');
    signal deploy_en    : std_logic := '0';
    signal harvest_k_en : std_logic := '0';
    signal harvest_h_en : std_logic := '0';
    signal energy_used  : std_logic_vector(23 downto 0) := (others => '0');
    signal pwm_mguk     : std_logic;
    signal pwm_mguh     : std_logic;
    signal duty_limited : std_logic_vector(15 downto 0);

    signal sim_done     : boolean := false;

    constant CLK_PERIOD : time := 20 ns;

    procedure wait_clk(n : integer) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

begin

    dut : entity work.power_arbiter
        port map (
            clk          => clk,
            rst_n        => rst_n,
            duty_in      => duty_in,
            deploy_en    => deploy_en,
            harvest_k_en => harvest_k_en,
            harvest_h_en => harvest_h_en,
            energy_used  => energy_used,
            pwm_mguk     => pwm_mguk,
            pwm_mguh     => pwm_mguh,
            duty_limited => duty_limited
        );

    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    stim_proc : process
    begin
        -- ----------------------------------------------------------------
        -- TESTE 1: Reset -> PWM em 0
        -- ----------------------------------------------------------------
        rst_n <= '0';
        wait_clk(3);
        assert pwm_mguk = '0' and pwm_mguh = '0'
            report "FALHA T1: PWMs deveriam ser 0 apos reset"
            severity error;

        rst_n <= '1';
        wait_clk(2);

        -- ----------------------------------------------------------------
        -- TESTE 2: Deploy com duty 50% -> PWM ativo, duty_limited repassa
        -- ----------------------------------------------------------------
        deploy_en <= '1';
        duty_in   <= std_logic_vector(to_unsigned(32768, 16)); -- 50%
        wait_clk(1100); -- mais que 1 periodo PWM (1000 ciclos)
        -- Verificar duty_limited
        assert unsigned(duty_limited) = to_unsigned(32768, 16)
            report "FALHA T2: duty_limited deveria ser 32768"
            severity error;
        -- Nota: nao verificamos pwm_mguk aqui pois e um sinal PWM oscilando

        -- ----------------------------------------------------------------
        -- TESTE 3: Energia excedida -> cortar deploy
        -- energy_used >= 1024000 (4 MJ em Q8)
        -- ----------------------------------------------------------------
        energy_used <= std_logic_vector(to_unsigned(1024000, 24));
        wait_clk(5);
        assert unsigned(duty_limited) = to_unsigned(0, 16)
            report "FALHA T3: Com energia excedida, duty_limited deveria ser 0"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 4: Energia normaliza -> deploy retorna
        -- ----------------------------------------------------------------
        energy_used <= std_logic_vector(to_unsigned(500000, 24));
        wait_clk(5);
        assert unsigned(duty_limited) = to_unsigned(32768, 16)
            report "FALHA T4: Com energia normal, duty_limited deveria voltar"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 5: Modo harvest K -> duty fixo 50%, duty_limited = 0
        -- (harvest nao conta como deploy de energia)
        -- ----------------------------------------------------------------
        deploy_en    <= '0';
        harvest_k_en <= '1';
        duty_in      <= (others => '0');
        wait_clk(5);
        assert unsigned(duty_limited) = to_unsigned(0, 16)
            report "FALHA T5: Em harvest, duty_limited deveria ser 0"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 6: Modo harvest H -> PWM MGU-H ativo
        -- ----------------------------------------------------------------
        harvest_k_en <= '0';
        harvest_h_en <= '1';
        wait_clk(1100);
        -- MGU-H deve gerar PWM, MGU-K nao
        report "T6: Harvest H ativo, verificar waveform do PWM MGU-H" severity note;

        -- ----------------------------------------------------------------
        -- TESTE 7: Tudo desligado -> ambos PWMs em 0
        -- ----------------------------------------------------------------
        harvest_h_en <= '0';
        deploy_en    <= '0';
        wait_clk(1100);
        -- Apos um periodo PWM completo, ambos devem estar em 0
        assert pwm_mguk = '0' and pwm_mguh = '0'
            report "FALHA T7: Com tudo desligado, PWMs deveriam ser 0"
            severity error;

        -- ----------------------------------------------------------------
        -- Fim
        -- ----------------------------------------------------------------
        wait_clk(5);
        report "=== TODOS OS TESTES DO POWER ARBITER CONCLUIDOS ===" severity note;
        sim_done <= true;
        wait;
    end process;

end architecture sim;
