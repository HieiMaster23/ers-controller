-------------------------------------------------------------------------------
-- ers_ctrl.vhd — Controle AUTO / MANUAL do deploy MGU-K
-- AUTO (sw=1): harvest no freio; deploy com throttle alto se SOC>SOC_LOW e budget
-- MANUAL (sw=0): harvest no freio; deploy so com sw_deploy=1 e SOC ok
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ers_pkg.all;

entity ers_ctrl is
  port (
    clk            : in  std_logic;
    rst_n          : in  std_logic;
    tick           : in  std_logic;
    sw_auto        : in  std_logic;  -- 1=AUTO, 0=MANUAL
    sw_deploy      : in  std_logic;  -- botao/switch deploy manual
    throttle       : in  unsigned(7 downto 0);
    soc            : in  unsigned(11 downto 0);
    deploy_ok      : in  std_logic;
    deploy_req     : out std_logic;
    mode_auto      : out std_logic
  );
end entity ers_ctrl;

architecture rtl of ers_ctrl is
  signal r_req  : std_logic := '0';
  signal r_auto : std_logic := '0';
begin
  deploy_req <= r_req;
  mode_auto  <= r_auto;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        r_req  <= '0';
        r_auto <= '0';
      else
        r_auto <= sw_auto;
        if tick = '1' then
          if sw_auto = '1' then
            -- AUTO: deploy se throttle alto, SOC acima do limiar e budget ok
            if to_integer(throttle) >= C_THROTTLE_DEPLOY_TH
               and to_integer(soc) > C_SOC_LOW
               and deploy_ok = '1' then
              r_req <= '1';
            else
              r_req <= '0';
            end if;
          else
            -- MANUAL: so com switch de deploy
            if sw_deploy = '1' and deploy_ok = '1' and to_integer(soc) > 0 then
              r_req <= '1';
            else
              r_req <= '0';
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
