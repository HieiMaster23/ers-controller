-------------------------------------------------------------------------------
-- tb_ers_plant.vhd — TB estrutural: ROM+seq+ctrl+mgu+store (checagens SOC/caps)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ers_pkg.all;

entity tb_ers_plant is
end entity tb_ers_plant;

architecture sim of tb_ers_plant is
  signal clk   : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal run   : std_logic := '0';
  signal done_sim : boolean := false;

  signal rom_addr, sample_idx : unsigned(9 downto 0);
  signal rom_data : std_logic_vector(31 downto 0);
  signal speed, throttle, brake : unsigned(7 downto 0);
  signal sector : unsigned(3 downto 0);
  signal tick, lap_done : std_logic;

  signal sw_auto : std_logic := '1';
  signal sw_deploy : std_logic := '0';
  signal deploy_req, mode_auto : std_logic;
  signal harvest_active, deploy_active : std_logic;
  signal power_signed : signed(7 downto 0);
  signal soc : unsigned(11 downto 0);
  signal empty_s, full_s, limit_hit, harvest_ok, deploy_ok : std_logic;
  signal e_h, e_d : unsigned(11 downto 0);
begin
  clk <= not clk after 10 ns when not done_sim else '0';

  u_rom : entity work.lap_rom
    port map (clk => clk, addr => rom_addr, data => rom_data);

  u_seq : entity work.lap_seq
    generic map (g_tick_div => 1, g_auto_repeat => false)
    port map (
      clk => clk, rst_n => rst_n, run => run, rom_data => rom_data,
      rom_addr => rom_addr, sample_idx => sample_idx,
      speed => speed, throttle => throttle, brake => brake, sector => sector,
      tick_pulse => tick, lap_done => lap_done);

  u_ctrl : entity work.ers_ctrl
    port map (
      clk => clk, rst_n => rst_n, tick => tick,
      sw_auto => sw_auto, sw_deploy => sw_deploy,
      throttle => throttle, soc => soc, deploy_ok => deploy_ok,
      deploy_req => deploy_req, mode_auto => mode_auto);

  u_mguk : entity work.mgu_k
    port map (
      clk => clk, rst_n => rst_n, tick => tick, brake => brake,
      deploy_req => deploy_req, harvest_ok => harvest_ok, deploy_ok => deploy_ok,
      harvest_active => harvest_active, deploy_active => deploy_active,
      power_signed => power_signed);

  u_store : entity work.energy_store
    port map (
      clk => clk, rst_n => rst_n, tick => tick, lap_reset => not run,
      power_signed => power_signed,
      harvest_active => harvest_active, deploy_active => deploy_active,
      soc => soc, empty => empty_s, full => full_s, limit_hit => limit_hit,
      harvest_ok => harvest_ok, deploy_ok => deploy_ok,
      e_harvest_lap => e_h, e_deploy_lap => e_d);

  stim : process
  begin
    report "PLANT TB: reset";
    rst_n <= '0'; run <= '0';
    wait for 100 ns;
    rst_n <= '1';
    wait for 40 ns;
    report "PLANT TB: AUTO run full lap";
    sw_auto <= '1';
    run <= '1';

    wait until lap_done = '1' for 50 ms;
    assert lap_done = '1' report "FAIL: lap did not finish" severity failure;

    assert to_integer(soc) >= 0 and to_integer(soc) <= C_SOC_MAX
      report "FAIL: SOC out of range" severity error;
    assert to_integer(e_h) <= C_E_HARVEST_LAP_MAX
      report "FAIL: harvest cap exceeded" severity error;
    assert to_integer(e_d) <= C_E_DEPLOY_LAP_MAX
      report "FAIL: deploy cap exceeded" severity error;
    assert not (harvest_active = '1' and deploy_active = '1')
      report "FAIL: both active at end" severity error;

    report "PLANT TB: SOC=" & integer'image(to_integer(soc))
      & " e_h=" & integer'image(to_integer(e_h))
      & " e_d=" & integer'image(to_integer(e_d));

    report "PLANT TB: MANUAL deploy burst";
    sw_auto <= '0';
    sw_deploy <= '1';
    for i in 0 to 50 loop
      wait until rising_edge(clk);
      assert not (harvest_active = '1' and deploy_active = '1')
        report "FAIL: mutual exclusion" severity error;
      assert to_integer(soc) <= C_SOC_MAX severity error;
    end loop;

    report "PLANT TB: PASS";
    done_sim <= true;
    wait;
  end process;

  -- Monitor continuo
  mon : process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '1' then
        assert not (harvest_active = '1' and deploy_active = '1')
          report "FAIL: harvest+deploy" severity error;
        assert to_integer(soc) <= C_SOC_MAX severity error;
        assert to_integer(e_h) <= C_E_HARVEST_LAP_MAX severity error;
        assert to_integer(e_d) <= C_E_DEPLOY_LAP_MAX severity error;
      end if;
    end if;
  end process;
end architecture sim;
