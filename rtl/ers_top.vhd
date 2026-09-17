-------------------------------------------------------------------------------
-- ers_top.vhd ? Top-level prototipo ERS EP4CE6 (MGU-K + store + VGA, sem MGU-H)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ers_pkg.all;

entity ers_top is
  generic (
    g_tick_div : integer := 5_000_000
  );
  port (
    clk_50         : in  std_logic;
    rst_n          : in  std_logic;
    sw_start       : in  std_logic;
    sw_auto_manual : in  std_logic;
    sw_deploy      : in  std_logic;
    led            : out std_logic_vector(3 downto 0);
    vga_hs         : out std_logic;
    vga_vs         : out std_logic;
    vga_r          : out std_logic_vector(3 downto 0);
    vga_g          : out std_logic_vector(3 downto 0);
    vga_b          : out std_logic_vector(3 downto 0)
  );
end entity ers_top;

architecture rtl of ers_top is
  signal px_clk : std_logic := '0';

  signal rom_addr   : unsigned(9 downto 0);
  signal rom_data   : std_logic_vector(31 downto 0);
  signal sample_idx : unsigned(9 downto 0);
  signal speed_rom  : unsigned(7 downto 0);
  signal throttle   : unsigned(7 downto 0);
  signal brake      : unsigned(7 downto 0);
  signal sector     : unsigned(3 downto 0);
  signal tick       : std_logic;
  signal lap_done   : std_logic;

  signal deploy_req     : std_logic;
  signal mode_auto      : std_logic;
  signal harvest_active : std_logic;
  signal deploy_active  : std_logic;
  signal power_signed   : signed(7 downto 0);

  signal soc           : unsigned(11 downto 0);
  signal empty_s       : std_logic;
  signal full_s        : std_logic;
  signal limit_hit     : std_logic;
  signal harvest_ok    : std_logic;
  signal deploy_ok     : std_logic;
  signal e_harvest_lap : unsigned(11 downto 0);
  signal e_deploy_lap  : unsigned(11 downto 0);

  signal visible : std_logic;
  signal vx, vy  : unsigned(9 downto 0);
  signal lap_reset : std_logic;

  signal speed_dyn : unsigned(7 downto 0);
  signal track_pos : unsigned(9 downto 0);
begin
  process (clk_50)
  begin
    if rising_edge(clk_50) then
      if rst_n = '0' then
        px_clk <= '0';
      else
        px_clk <= not px_clk;
      end if;
    end if;
  end process;

  lap_reset <= not sw_start;

  u_rom : entity work.lap_rom
    port map (
      clk  => clk_50,
      addr => rom_addr,
      data => rom_data
    );

  u_seq : entity work.lap_seq
    generic map (
      g_tick_div    => g_tick_div,
      g_auto_repeat => true
    )
    port map (
      clk        => clk_50,
      rst_n      => rst_n,
      run        => sw_start,
      rom_data   => rom_data,
      rom_addr   => rom_addr,
      sample_idx => sample_idx,
      speed      => speed_rom,
      throttle   => throttle,
      brake      => brake,
      sector     => sector,
      tick_pulse => tick,
      lap_done   => lap_done
    );

  -- Velocidade e posicao na pista a partir de acel/freio (nao ritmo fixo)
  u_motion : entity work.track_motion
    port map (
      clk      => clk_50,
      rst_n    => rst_n,
      tick     => tick,
      enable   => sw_start,
      throttle => throttle,
      brake    => brake,
      speed    => speed_dyn,
      pos      => track_pos
    );

  u_ctrl : entity work.ers_ctrl
    port map (
      clk        => clk_50,
      rst_n      => rst_n,
      tick       => tick,
      sw_auto    => sw_auto_manual,
      sw_deploy  => sw_deploy,
      throttle   => throttle,
      soc        => soc,
      deploy_ok  => deploy_ok,
      deploy_req => deploy_req,
      mode_auto  => mode_auto
    );

  u_mguk : entity work.mgu_k
    port map (
      clk            => clk_50,
      rst_n          => rst_n,
      tick           => tick,
      brake          => brake,
      deploy_req     => deploy_req,
      harvest_ok     => harvest_ok,
      deploy_ok      => deploy_ok,
      harvest_active => harvest_active,
      deploy_active  => deploy_active,
      power_signed   => power_signed
    );

  u_store : entity work.energy_store
    port map (
      clk            => clk_50,
      rst_n          => rst_n,
      tick           => tick,
      lap_reset      => lap_reset,
      power_signed   => power_signed,
      harvest_active => harvest_active,
      deploy_active  => deploy_active,
      soc            => soc,
      empty          => empty_s,
      full           => full_s,
      limit_hit      => limit_hit,
      harvest_ok     => harvest_ok,
      deploy_ok      => deploy_ok,
      e_harvest_lap  => e_harvest_lap,
      e_deploy_lap   => e_deploy_lap
    );

  u_vga : entity work.vga_sync
    port map (
      px_clk  => px_clk,
      rst_n   => rst_n,
      hsync   => vga_hs,
      vsync   => vga_vs,
      visible => visible,
      x       => vx,
      y       => vy
    );

  u_dash : entity work.dash_vga
    port map (
      px_clk         => px_clk,
      rst_n          => rst_n,
      visible        => visible,
      x              => vx,
      y              => vy,
      track_pos      => track_pos,
      speed          => speed_dyn,
      throttle       => throttle,
      brake          => brake,
      soc            => soc,
      harvest_active => harvest_active,
      deploy_active  => deploy_active,
      mode_auto      => mode_auto,
      vga_r          => vga_r,
      vga_g          => vga_g,
      vga_b          => vga_b
    );

  u_leds : entity work.dash_leds
    port map (
      harvest_active => harvest_active,
      deploy_active  => deploy_active,
      limit_hit      => limit_hit,
      full           => full_s,
      led            => led
    );
end architecture rtl;
