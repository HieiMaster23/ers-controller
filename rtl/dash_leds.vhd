-------------------------------------------------------------------------------
-- dash_leds.vhd — LEDs de status do ERS
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity dash_leds is
  port (
    harvest_active : in  std_logic;
    deploy_active  : in  std_logic;
    limit_hit      : in  std_logic;
    full           : in  std_logic;
    led            : out std_logic_vector(3 downto 0)
  );
end entity dash_leds;

architecture rtl of dash_leds is
begin
  led(0) <= harvest_active;
  led(1) <= deploy_active;
  led(2) <= limit_hit;
  led(3) <= full;
end architecture rtl;
