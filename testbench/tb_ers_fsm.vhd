-- ============================================================================
-- Arquivo  : tb_ers_fsm.vhd
-- Autor    : Rafael
-- Data     : 2026-04-06
-- Descricao: Testbench da FSM do ERS. Testa todas as transicoes de estado,
--            prioridade de FAULT, e condicoes de borda.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ers_fsm is
end entity tb_ers_fsm;

architecture sim of tb_ers_fsm is

    -- Sinais do DUT
    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';
    signal brake_pres   : std_logic_vector(11 downto 0) := (others => '0');
    signal throttle     : std_logic_vector(11 downto 0) := (others => '0');
    signal soc_in       : std_logic_vector(11 downto 0) := (others => '0');
    signal turbo_rpm    : std_logic_vector(15 downto 0) := (others => '0');
    signal energy_used  : std_logic_vector(23 downto 0) := (others => '0');
    signal harvest_k_en : std_logic;
    signal harvest_h_en : std_logic;
    signal deploy_en    : std_logic;
    signal fault_active : std_logic;
    signal ers_mode     : std_logic_vector(2 downto 0);

    signal sim_done     : boolean := false;

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

    -- Procedimento para esperar N ciclos de clock
    procedure wait_clk(n : integer) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

begin

    -- ========================================================================
    -- Instancia do DUT
    -- ========================================================================
    dut : entity work.ers_fsm
        port map (
            clk          => clk,
            rst_n        => rst_n,
            brake_pres   => brake_pres,
            throttle     => throttle,
            soc_in       => soc_in,
            turbo_rpm    => turbo_rpm,
            energy_used  => energy_used,
            harvest_k_en => harvest_k_en,
            harvest_h_en => harvest_h_en,
            deploy_en    => deploy_en,
            fault_active => fault_active,
            ers_mode     => ers_mode
        );

    -- ========================================================================
    -- Geracao de clock
    -- ========================================================================
    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    -- ========================================================================
    -- Processo de estimulo
    -- ========================================================================
    stim_proc : process
    begin
        -- ----------------------------------------------------------------
        -- TESTE 1: Reset -> STANDBY
        -- SoC inicializado em 70% para evitar FAULT imediato apos reset
        -- ----------------------------------------------------------------
        rst_n  <= '0';
        soc_in <= std_logic_vector(to_unsigned(2867, 12)); -- ~70%
        wait_clk(3);
        assert ers_mode = "000"
            report "FALHA T1: Apos reset, estado deveria ser STANDBY (000)"
            severity error;

        rst_n <= '1';
        wait_clk(2);
        assert ers_mode = "000"
            report "FALHA T1: Apos soltar reset, deve permanecer STANDBY"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 2: STANDBY -> HARVESTING_K (freio forte, SoC ok)
        -- brake_pres = 1000 (> 512), soc = 2867 (~70%, < 3685)
        -- ----------------------------------------------------------------
        brake_pres <= std_logic_vector(to_unsigned(1000, 12));
        -- soc_in ja esta em 2867 (definido no T1)
        wait_clk(2);
        assert ers_mode = "001"
            report "FALHA T2: Deveria transitar para HARVESTING_K (001)"
            severity error;
        assert harvest_k_en = '1'
            report "FALHA T2: harvest_k_en deveria ser '1'"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 3: HARVESTING_K -> STANDBY (soltar freio)
        -- ----------------------------------------------------------------
        brake_pres <= std_logic_vector(to_unsigned(100, 12)); -- < 512
        wait_clk(2);
        assert ers_mode = "000"
            report "FALHA T3: Deveria voltar para STANDBY (000)"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 4: STANDBY -> HARVESTING_H (turbo alto, SoC ok)
        -- turbo_rpm = 50000 (> 40000), soc = 2867
        -- ----------------------------------------------------------------
        brake_pres <= (others => '0');
        turbo_rpm  <= std_logic_vector(to_unsigned(50000, 16));
        wait_clk(2);
        assert ers_mode = "010"
            report "FALHA T4: Deveria transitar para HARVESTING_H (010)"
            severity error;
        assert harvest_h_en = '1'
            report "FALHA T4: harvest_h_en deveria ser '1'"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 5: HARVESTING_H -> DEPLOYING (acelerador forte, prioridade)
        -- throttle = 3000 (> 2048), soc > 1024, energy < max
        -- ----------------------------------------------------------------
        throttle <= std_logic_vector(to_unsigned(3000, 12));
        wait_clk(2);
        assert ers_mode = "011"
            report "FALHA T5: Deveria transitar para DEPLOYING (011)"
            severity error;
        assert deploy_en = '1'
            report "FALHA T5: deploy_en deveria ser '1'"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 6: DEPLOYING -> FAULT (SoC muito baixo)
        -- soc = 500 (< 819 = 20%)
        -- ----------------------------------------------------------------
        soc_in <= std_logic_vector(to_unsigned(500, 12));
        wait_clk(2);
        assert ers_mode = "111"
            report "FALHA T6: Deveria transitar para FAULT (111)"
            severity error;
        assert fault_active = '1'
            report "FALHA T6: fault_active deveria ser '1'"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 7: FAULT -> STANDBY (SoC normaliza)
        -- soc = 2867 (~70%)
        -- ----------------------------------------------------------------
        soc_in   <= std_logic_vector(to_unsigned(2867, 12));
        throttle <= (others => '0');
        turbo_rpm <= (others => '0');
        wait_clk(2);
        assert ers_mode = "000"
            report "FALHA T7: Deveria sair de FAULT para STANDBY (000)"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 8: FAULT por SoC alto (> 95%)
        -- soc = 3950 (> 3890)
        -- ----------------------------------------------------------------
        soc_in <= std_logic_vector(to_unsigned(3950, 12));
        wait_clk(2);
        assert ers_mode = "111"
            report "FALHA T8: SoC > 95% deveria causar FAULT (111)"
            severity error;

        -- Normalizar
        soc_in <= std_logic_vector(to_unsigned(2867, 12));
        wait_clk(2);

        -- ----------------------------------------------------------------
        -- TESTE 9: Prioridade DEPLOY > HARVEST_K
        -- Freio e acelerador simultaneos (conflito)
        -- ----------------------------------------------------------------
        brake_pres <= std_logic_vector(to_unsigned(2000, 12));
        throttle   <= std_logic_vector(to_unsigned(3000, 12));
        soc_in     <= std_logic_vector(to_unsigned(2867, 12));
        wait_clk(2);
        assert ers_mode = "011"
            report "FALHA T9: DEPLOYING deve ter prioridade sobre HARVESTING_K"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 10: DEPLOYING bloqueado quando energia excede limite
        -- energy_used > ENERGY_MAX (1024000)
        -- ----------------------------------------------------------------
        throttle    <= (others => '0');
        brake_pres  <= (others => '0');
        wait_clk(2); -- volta para STANDBY

        energy_used <= std_logic_vector(to_unsigned(1100000, 24));
        throttle    <= std_logic_vector(to_unsigned(3000, 12));
        wait_clk(2);
        assert ers_mode = "000"
            report "FALHA T10: Nao deveria fazer DEPLOY com energia excedida"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 11: HARVEST_K bloqueado quando SoC > 90%
        -- soc = 3700 (> 3685)
        -- ----------------------------------------------------------------
        throttle    <= (others => '0');
        energy_used <= (others => '0');
        soc_in      <= std_logic_vector(to_unsigned(3700, 12)); -- ~90.3%
        brake_pres  <= std_logic_vector(to_unsigned(2000, 12));
        wait_clk(2);
        assert ers_mode = "000"
            report "FALHA T11: Nao deveria fazer HARVEST com SoC > 90%"
            severity error;

        -- ----------------------------------------------------------------
        -- TESTE 12: Transicao HARVESTING_K -> HARVESTING_H
        -- Soltar freio com turbo alto
        -- ----------------------------------------------------------------
        soc_in     <= std_logic_vector(to_unsigned(2867, 12));
        brake_pres <= std_logic_vector(to_unsigned(2000, 12));
        turbo_rpm  <= std_logic_vector(to_unsigned(50000, 16));
        wait_clk(2);
        assert ers_mode = "001"
            report "FALHA T12a: Deveria estar em HARVESTING_K"
            severity error;

        brake_pres <= std_logic_vector(to_unsigned(100, 12)); -- soltar freio
        wait_clk(2);
        assert ers_mode = "010"
            report "FALHA T12b: Deveria transitar para HARVESTING_H"
            severity error;

        -- ----------------------------------------------------------------
        -- Fim dos testes
        -- ----------------------------------------------------------------
        brake_pres  <= (others => '0');
        throttle    <= (others => '0');
        turbo_rpm   <= (others => '0');
        soc_in      <= std_logic_vector(to_unsigned(2867, 12));
        energy_used <= (others => '0');
        wait_clk(5);

        report "=== TODOS OS TESTES DA FSM CONCLUIDOS ===" severity note;
        sim_done <= true;
        wait;
    end process;

end architecture sim;
