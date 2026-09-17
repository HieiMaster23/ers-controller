-------------------------------------------------------------------------------
-- vga_sync.vhd — 640x480@60 a partir de ~25 MHz (50 MHz / 2)
-- Timing: H 640+16+96+48=800 ; V 480+10+2+33=525
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_sync is
  port (
    px_clk  : in  std_logic;
    rst_n   : in  std_logic;
    hsync   : out std_logic;
    vsync   : out std_logic;
    visible : out std_logic;
    x       : out unsigned(9 downto 0);  -- 0..639 quando visible
    y       : out unsigned(9 downto 0)   -- 0..479
  );
end entity vga_sync;

architecture rtl of vga_sync is
  constant H_VISIBLE : integer := 640;
  constant H_FP      : integer := 16;
  constant H_SYNC    : integer := 96;
  constant H_BP      : integer := 48;
  constant H_TOTAL   : integer := 800;

  constant V_VISIBLE : integer := 480;
  constant V_FP      : integer := 10;
  constant V_SYNC    : integer := 2;
  constant V_BP      : integer := 33;
  constant V_TOTAL   : integer := 525;

  signal r_h : integer range 0 to H_TOTAL-1 := 0;
  signal r_v : integer range 0 to V_TOTAL-1 := 0;
begin
  process (px_clk)
  begin
    if rising_edge(px_clk) then
      if rst_n = '0' then
        r_h <= 0;
        r_v <= 0;
      else
        if r_h = H_TOTAL - 1 then
          r_h <= 0;
          if r_v = V_TOTAL - 1 then
            r_v <= 0;
          else
            r_v <= r_v + 1;
          end if;
        else
          r_h <= r_h + 1;
        end if;
      end if;
    end if;
  end process;

  -- HSYNC/VSYNC ativos em baixo (padrao VGA)
  hsync <= '0' when (r_h >= H_VISIBLE + H_FP and r_h < H_VISIBLE + H_FP + H_SYNC) else '1';
  vsync <= '0' when (r_v >= V_VISIBLE + V_FP and r_v < V_VISIBLE + V_FP + V_SYNC) else '1';

  visible <= '1' when (r_h < H_VISIBLE and r_v < V_VISIBLE) else '0';
  x <= to_unsigned(r_h, 10) when r_h < H_VISIBLE else (others => '0');
  y <= to_unsigned(r_v, 10) when r_v < V_VISIBLE else (others => '0');
end architecture rtl;
