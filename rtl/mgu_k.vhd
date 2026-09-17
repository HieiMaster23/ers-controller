-------------------------------------------------------------------------------
-- mgu_k.vhd — Motor-Gerador Unidade K (so MGU-K; v1 sem MGU-H)
-- Harvest se freio alto; deploy se ctrl pedir. Nunca ambos. Clamp potencia.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ers_pkg.all;

entity mgu_k is
  port (
    clk            : in  std_logic;
    rst_n          : in  std_logic;
    tick           : in  std_logic;
    brake          : in  unsigned(7 downto 0);
    deploy_req     : in  std_logic;   -- pedido do controlador
    harvest_ok     : in  std_logic;   -- energia_store permite harvest
    deploy_ok      : in  std_logic;   -- energia_store permite deploy
    harvest_active : out std_logic;
    deploy_active  : out std_logic;
    power_signed   : out signed(7 downto 0)  -- +harvest, -deploy
  );
end entity mgu_k;

architecture rtl of mgu_k is
  signal r_harv : std_logic := '0';
  signal r_dep  : std_logic := '0';
  signal r_pwr  : signed(7 downto 0) := (others => '0');
begin
  harvest_active <= r_harv;
  deploy_active  <= r_dep;
  power_signed   <= r_pwr;

  process (clk)
    variable v_want_h : std_logic;
    variable v_want_d : std_logic;
    variable v_p      : integer;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        r_harv <= '0';
        r_dep  <= '0';
        r_pwr  <= (others => '0');
      elsif tick = '1' then
        v_want_h := '0';
        v_want_d := '0';
        if to_integer(brake) > C_BRAKE_HARVEST_TH then
          v_want_h := '1';
        end if;
        if deploy_req = '1' then
          v_want_d := '1';
        end if;

        -- Nunca ambos: harvest tem prioridade sobre deploy
        if v_want_h = '1' and harvest_ok = '1' then
          r_harv <= '1';
          r_dep  <= '0';
          -- potencia proporcional ao freio, clamp P_MAX
          v_p := to_integer(brake) / 4;  -- 0..63
          if v_p > C_P_MAX then
            v_p := C_P_MAX;
          end if;
          if v_p < 1 then
            v_p := 1;
          end if;
          r_pwr <= to_signed(v_p, 8);
        elsif v_want_d = '1' and deploy_ok = '1' then
          r_harv <= '0';
          r_dep  <= '1';
          v_p := C_P_MAX;
          r_pwr <= to_signed(-v_p, 8);
        else
          r_harv <= '0';
          r_dep  <= '0';
          r_pwr  <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
