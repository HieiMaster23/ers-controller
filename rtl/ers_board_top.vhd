-------------------------------------------------------------------------------
-- ers_board_top.vhd ? Empacotamento RZ-EasyFPGA A2.2 / EP4CE6E22C8
-- VGA 1 bit/cor, botoes ativos em baixo, LEDs ativos em baixo.
-- Modo feira: tick ~10 ms e volta em loop.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ers_board_top is
  port (
    clk_50   : in  std_logic;
    rst_n    : in  std_logic;                      -- KEY reset, ativo baixo
    key_n    : in  std_logic_vector(2 downto 0);   -- 0=start/hold, 1=auto, 2=deploy
    led      : out std_logic_vector(3 downto 0);   -- ativo baixo na placa
    vga_hs   : out std_logic;
    vga_vs   : out std_logic;
    vga_r    : out std_logic;
    vga_g    : out std_logic;
    vga_b    : out std_logic
  );
end entity ers_board_top;

architecture rtl of ers_board_top is
  signal sw_start       : std_logic;
  signal sw_auto_manual : std_logic;
  signal sw_deploy      : std_logic;
  signal led_int        : std_logic_vector(3 downto 0);
  signal vga_r4         : std_logic_vector(3 downto 0);
  signal vga_g4         : std_logic_vector(3 downto 0);
  signal vga_b4         : std_logic_vector(3 downto 0);
begin
  -- Pull-up tipico: solto='1'. Solto em KEY0 => roda a volta (bom para feira).
  -- Pressionar KEY0 zera/segura o sequenciador.
  sw_start       <= key_n(0);
  sw_auto_manual <= key_n(1);          -- solto = AUTO
  sw_deploy      <= not key_n(2);      -- pressionado = pede deploy

  u_core : entity work.ers_top
    generic map (
      g_tick_div => 500_000            -- 50 MHz / 5e5 = 10 ms (demo)
    )
    port map (
      clk_50         => clk_50,
      rst_n          => rst_n,
      sw_start       => sw_start,
      sw_auto_manual => sw_auto_manual,
      sw_deploy      => sw_deploy,
      led            => led_int,
      vga_hs         => vga_hs,
      vga_vs         => vga_vs,
      vga_r          => vga_r4,
      vga_g          => vga_g4,
      vga_b          => vga_b4
    );

  -- LEDs da placa acendem em nivel baixo
  led <= not led_int;

  -- DAC resistivo 1 bit: usa o MSB da cor 4:4:4
  vga_r <= vga_r4(3);
  vga_g <= vga_g4(3);
  vga_b <= vga_b4(3);
end architecture rtl;
