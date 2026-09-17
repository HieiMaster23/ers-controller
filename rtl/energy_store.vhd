-------------------------------------------------------------------------------
-- energy_store.vhd — Armazenamento de energia (SOC inteiro) + orcamentos por volta
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ers_pkg.all;

entity energy_store is
  port (
    clk            : in  std_logic;
    rst_n          : in  std_logic;
    tick           : in  std_logic;
    lap_reset      : in  std_logic;  -- zera contadores de volta (ex.: ao reiniciar)
    power_signed   : in  signed(7 downto 0);  -- +charge, -discharge
    harvest_active : in  std_logic;
    deploy_active  : in  std_logic;
    soc            : out unsigned(11 downto 0);
    empty          : out std_logic;
    full           : out std_logic;
    limit_hit      : out std_logic;
    harvest_ok     : out std_logic;
    deploy_ok      : out std_logic;
    e_harvest_lap  : out unsigned(11 downto 0);
    e_deploy_lap   : out unsigned(11 downto 0)
  );
end entity energy_store;

architecture rtl of energy_store is
  signal r_soc  : integer range 0 to C_SOC_MAX := C_SOC_INIT;
  signal r_eh   : integer range 0 to C_E_HARVEST_LAP_MAX := 0;
  signal r_ed   : integer range 0 to C_E_DEPLOY_LAP_MAX  := 0;
  signal r_lim  : std_logic := '0';
  signal r_hok  : std_logic := '1';
  signal r_dok  : std_logic := '1';
begin
  soc           <= to_unsigned(r_soc, 12);
  empty         <= '1' when r_soc = 0 else '0';
  full          <= '1' when r_soc >= C_SOC_MAX else '0';
  limit_hit     <= r_lim;
  harvest_ok    <= r_hok;
  deploy_ok     <= r_dok;
  e_harvest_lap <= to_unsigned(r_eh, 12);
  e_deploy_lap  <= to_unsigned(r_ed, 12);

  process (clk)
    variable v_p   : integer;
    variable v_soc : integer;
    variable v_eh  : integer;
    variable v_ed  : integer;
    variable v_lim : std_logic;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        r_soc <= C_SOC_INIT;
        r_eh  <= 0;
        r_ed  <= 0;
        r_lim <= '0';
        r_hok <= '1';
        r_dok <= '1';
      else
        if lap_reset = '1' then
          r_eh  <= 0;
          r_ed  <= 0;
          r_lim <= '0';
          r_hok <= '1';
          r_dok <= '1';
        end if;

        if tick = '1' then
          v_p   := to_integer(power_signed);
          v_soc := r_soc;
          v_eh  := r_eh;
          v_ed  := r_ed;
          v_lim := r_lim;

          if harvest_active = '1' and v_p > 0 then
            if v_eh >= C_E_HARVEST_LAP_MAX then
              v_lim := '1';
            else
              if v_eh + v_p > C_E_HARVEST_LAP_MAX then
                v_p   := C_E_HARVEST_LAP_MAX - v_eh;
                v_lim := '1';
              end if;
              if v_soc + v_p > C_SOC_MAX then
                v_p   := C_SOC_MAX - v_soc;
                v_lim := '1';
              end if;
              v_soc := v_soc + v_p;
              v_eh  := v_eh + v_p;
            end if;
          elsif deploy_active = '1' and v_p < 0 then
            v_p := -v_p;  -- magnitude
            if v_ed >= C_E_DEPLOY_LAP_MAX then
              v_lim := '1';
            else
              if v_ed + v_p > C_E_DEPLOY_LAP_MAX then
                v_p   := C_E_DEPLOY_LAP_MAX - v_ed;
                v_lim := '1';
              end if;
              if v_soc < v_p then
                v_p   := v_soc;
                v_lim := '1';
              end if;
              v_soc := v_soc - v_p;
              v_ed  := v_ed + v_p;
            end if;
          end if;

          r_soc <= v_soc;
          r_eh  <= v_eh;
          r_ed  <= v_ed;
          r_lim <= v_lim;
          -- inibe direcao se orcamento esgotado ou SOC extremo
          if v_eh >= C_E_HARVEST_LAP_MAX or v_soc >= C_SOC_MAX then
            r_hok <= '0';
          else
            r_hok <= '1';
          end if;
          if v_ed >= C_E_DEPLOY_LAP_MAX or v_soc = 0 then
            r_dok <= '0';
          else
            r_dok <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
