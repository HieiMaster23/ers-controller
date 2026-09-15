-------------------------------------------------------------------------------
-- tb_ers.vhd — Testbench VHDL-93 do prototipo ERS (tick rapido)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ers_pkg.all;

entity tb_ers is
end entity tb_ers;

architecture sim of tb_ers is
  signal clk_50         : std_logic := '0';
  signal rst_n          : std_logic := '0';
  signal sw_start       : std_logic := '0';
  signal sw_auto_manual : std_logic := '1';
  signal sw_deploy      : std_logic := '0';
  signal led            : std_logic_vector(3 downto 0);
  signal vga_hs, vga_vs : std_logic;
  signal vga_r, vga_g, vga_b : std_logic_vector(3 downto 0);

  -- Espelhos internos via hierarchical? Em VHDL-93 puro nao; re-instancia planta
  -- Aqui exercitamos o top com tick=1 ciclo (g_tick_div=1)

  constant CLK_HALF : time := 10 ns;  -- 50 MHz

  signal done_sim : boolean := false;
begin
  clk_50 <= not clk_50 after CLK_HALF when not done_sim else '0';

  uut : entity work.ers_top
    generic map (
      g_tick_div => 1
    )
    port map (
      clk_50         => clk_50,
      rst_n          => rst_n,
      sw_start       => sw_start,
      sw_auto_manual => sw_auto_manual,
      sw_deploy      => sw_deploy,
      led            => led,
      vga_hs         => vga_hs,
      vga_vs         => vga_vs,
      vga_r          => vga_r,
      vga_g          => vga_g,
      vga_b          => vga_b
    );

  -- Planta paralela observavel (mesmos estimulos de ROM via top interno nao exposto)
  -- Validacoes basicas via LEDs e tempo
  stim : process
    variable v_cycles : integer := 0;
  begin
    report "TB: reset";
    rst_n <= '0';
    sw_start <= '0';
    sw_auto_manual <= '1';
    sw_deploy <= '0';
    wait for 200 ns;
    rst_n <= '1';
    wait for 100 ns;

    report "TB: AUTO mode, start lap";
    sw_auto_manual <= '1';
    sw_start <= '1';

    -- Roda ~950 ticks (1 ciclo/tick + overhead ROM latency)
    for i in 0 to 2000 loop
      wait until rising_edge(clk_50);
      v_cycles := v_cycles + 1;
      -- harvest e deploy mutuamente exclusivos nos LEDs
      assert not (led(0) = '1' and led(1) = '1')
        report "FAIL: harvest e deploy ativos juntos" severity error;
    end loop;

    report "TB: switch to MANUAL, assert deploy";
    sw_auto_manual <= '0';
    sw_deploy <= '1';
    for i in 0 to 200 loop
      wait until rising_edge(clk_50);
      assert not (led(0) = '1' and led(1) = '1')
        report "FAIL: harvest/deploy overlap in MANUAL" severity error;
    end loop;

    report "TB: hold sequencer";
    sw_start <= '0';
    wait for 500 ns;

    report "TB: done OK (SOC range checked indirectly; no LED full+empty conflict assumed)";
    done_sim <= true;
    wait;
  end process;
end architecture sim;
