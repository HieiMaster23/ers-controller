-------------------------------------------------------------------------------
-- lap_seq.vhd — Sequenciador de volta: avanca amostra a cada tick de planta
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ers_pkg.all;

entity lap_seq is
  generic (
    g_tick_div    : integer := 5_000_000;  -- 50 MHz / 10 = 5e6 => 100 ms
    g_auto_repeat : boolean := false       -- false: segura ultima amostra
  );
  port (
    clk          : in  std_logic;
    rst_n        : in  std_logic;
    run          : in  std_logic;          -- 0=hold/reset idx, 1=roda
    rom_data     : in  std_logic_vector(31 downto 0);
    rom_addr     : out unsigned(9 downto 0);
    sample_idx   : out unsigned(9 downto 0);
    speed        : out unsigned(7 downto 0);
    throttle     : out unsigned(7 downto 0);
    brake        : out unsigned(7 downto 0);
    sector       : out unsigned(3 downto 0);
    tick_pulse   : out std_logic;          -- 1 ciclo a cada tick
    lap_done     : out std_logic
  );
end entity lap_seq;

architecture rtl of lap_seq is
  signal r_div   : integer range 0 to g_tick_div := 0;
  signal r_idx   : unsigned(9 downto 0) := (others => '0');
  signal r_tick  : std_logic := '0';
  signal r_done  : std_logic := '0';
  signal r_spd   : unsigned(7 downto 0) := (others => '0');
  signal r_thr   : unsigned(7 downto 0) := (others => '0');
  signal r_brk   : unsigned(7 downto 0) := (others => '0');
  signal r_sec   : unsigned(3 downto 0) := (others => '0');
begin
  rom_addr   <= r_idx;
  sample_idx <= r_idx;
  speed      <= r_spd;
  throttle   <= r_thr;
  brake      <= r_brk;
  sector     <= r_sec;
  tick_pulse <= r_tick;
  lap_done   <= r_done;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' or run = '0' then
        r_div  <= 0;
        r_idx  <= (others => '0');
        r_tick <= '0';
        r_done <= '0';
        r_spd  <= (others => '0');
        r_thr  <= (others => '0');
        r_brk  <= (others => '0');
        r_sec  <= (others => '0');
      else
        r_tick <= '0';
        -- atualiza campos a partir da ROM (1 ciclo de latencia ok)
        r_spd <= f_unpack_speed(rom_data);
        r_thr <= f_unpack_throttle(rom_data);
        r_brk <= f_unpack_brake(rom_data);
        r_sec <= f_unpack_sector(rom_data);

        if r_div >= g_tick_div - 1 then
          r_div  <= 0;
          r_tick <= '1';
          if r_idx >= to_unsigned(C_LAP_LEN - 1, 10) then
            r_done <= '1';
            if g_auto_repeat then
              r_idx <= (others => '0');
            end if;
            -- senao: segura ultimo indice
          else
            r_idx  <= r_idx + 1;
            r_done <= '0';
          end if;
        else
          r_div <= r_div + 1;
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
