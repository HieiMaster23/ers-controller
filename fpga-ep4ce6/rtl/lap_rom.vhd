-------------------------------------------------------------------------------
-- lap_rom.vhd — ROM 900 x 32b (array constante = MIF; sem IP MegaWizard)
-- MIF canonico: stim/volta_sintetica.mif (ver stim/SCALE.md)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lap_rom_init_pkg.all;

entity lap_rom is
  port (
    clk  : in  std_logic;
    addr : in  unsigned(9 downto 0);          -- 0..899
    data : out std_logic_vector(31 downto 0)
  );
end entity lap_rom;

architecture rtl of lap_rom is
  signal r_data : std_logic_vector(31 downto 0) := (others => '0');
begin
  process (clk)
    variable v_addr : integer;
  begin
    if rising_edge(clk) then
      v_addr := to_integer(addr);
      if v_addr < 0 then
        v_addr := 0;
      elsif v_addr > 899 then
        v_addr := 899;
      end if;
      r_data <= C_LAP_ROM(v_addr);
    end if;
  end process;
  data <= r_data;
end architecture rtl;
