-------------------------------------------------------------------------------
-- track_motion.vhd ? Velocidade e posicao na pista a partir de throttle/brake
-- Integra aceleracao/freio (nao avanca em ritmo fixo).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity track_motion is
  generic (
    g_perim : integer := 1024;  -- comprimento logico da volta
    g_vmin  : integer := 8;
    g_vmax  : integer := 180
  );
  port (
    clk      : in  std_logic;
    rst_n    : in  std_logic;
    tick     : in  std_logic;
    enable   : in  std_logic;
    throttle : in  unsigned(7 downto 0);
    brake    : in  unsigned(7 downto 0);
    speed    : out unsigned(7 downto 0);
    pos      : out unsigned(9 downto 0)   -- 0 .. g_perim-1
  );
end entity track_motion;

architecture rtl of track_motion is
  signal r_v : integer range 0 to g_vmax := g_vmin;
  signal r_s : integer range 0 to g_perim - 1 := 0;
begin
  speed <= to_unsigned(r_v, 8);
  pos   <= to_unsigned(r_s, 10);

  process (clk)
    variable v : integer;
    variable s : integer;
    variable accel : integer;
    variable decel : integer;
  begin
    if rising_edge(clk) then
      if rst_n = '0' or enable = '0' then
        r_v <= g_vmin;
        r_s <= 0;
      elsif tick = '1' then
        -- Acelera com pedal; freio pesa mais (comportamento de pista)
        accel := to_integer(throttle) / 24;
        decel := to_integer(brake) / 12;
        v := r_v + accel - decel - 1;  -- -1 = arrasto leve
        if v < g_vmin then
          v := g_vmin;
        elsif v > g_vmax then
          v := g_vmax;
        end if;
        s := r_s + v;
        if s >= g_perim then
          s := s - g_perim;
        end if;
        r_v <= v;
        r_s <= s;
      end if;
    end if;
  end process;
end architecture rtl;
