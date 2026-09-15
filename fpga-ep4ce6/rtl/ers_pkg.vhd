-------------------------------------------------------------------------------
-- ers_pkg.vhd — Constantes do prototipo ERS (unidades escaladas, NAO oficiais FIA)
-- VHDL-93 / Cyclone IV EP4CE6
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ers_pkg is

  -- Comprimento da volta sintetica (amostras a cada tick de planta)
  constant C_LAP_LEN : integer := 900;

  -- Tick de planta alvo: 100 ms. Em hardware: g_tick_div = clk_hz/10.
  -- LSB de potencia: 1 unidade de potencia * 1 tick = 1 unidade de energia (SOC).
  constant C_TICK_MS : integer := 100;

  -- Potencia maxima do MGU-K (unidades / tick). Clamp harvest/deploy.
  constant C_P_MAX : integer := 40;

  -- Limites de energia por volta (saturam e inibem a direcao)
  constant C_E_HARVEST_LAP_MAX : integer := 1800;
  constant C_E_DEPLOY_LAP_MAX  : integer := 1800;

  -- State of Charge: 0 .. SOC_MAX. SOC_LOW = limiar de deploy em AUTO.
  constant C_SOC_MAX : integer := 4000;
  constant C_SOC_LOW : integer := 500;
  constant C_SOC_INIT : integer := 2000;

  -- Limiar de freio para harvest (throttle/brake 0..255)
  constant C_BRAKE_HARVEST_TH : integer := 80;
  -- Limiar de acelerador para deploy automatico
  constant C_THROTTLE_DEPLOY_TH : integer := 180;

  -- Larguras
  subtype t_u8  is unsigned(7 downto 0);
  subtype t_u4  is unsigned(3 downto 0);
  subtype t_soc is unsigned(11 downto 0);  -- cabe 4000
  subtype t_e   is unsigned(11 downto 0);  -- energia por volta
  subtype t_pwr is signed(7 downto 0);     -- potencia com sinal (-P_MAX..+P_MAX)

  -- Helpers de empacotamento da ROM (palavra 32b)
  -- [27:24]=sector [23:16]=brake [15:8]=throttle [7:0]=speed
  function f_unpack_speed    (w : std_logic_vector(31 downto 0)) return unsigned;
  function f_unpack_throttle (w : std_logic_vector(31 downto 0)) return unsigned;
  function f_unpack_brake    (w : std_logic_vector(31 downto 0)) return unsigned;
  function f_unpack_sector   (w : std_logic_vector(31 downto 0)) return unsigned;

end package ers_pkg;

package body ers_pkg is

  function f_unpack_speed (w : std_logic_vector(31 downto 0)) return unsigned is
  begin
    return unsigned(w(7 downto 0));
  end function;

  function f_unpack_throttle (w : std_logic_vector(31 downto 0)) return unsigned is
  begin
    return unsigned(w(15 downto 8));
  end function;

  function f_unpack_brake (w : std_logic_vector(31 downto 0)) return unsigned is
  begin
    return unsigned(w(23 downto 16));
  end function;

  function f_unpack_sector (w : std_logic_vector(31 downto 0)) return unsigned is
  begin
    return unsigned(w(27 downto 24));
  end function;

end package body ers_pkg;
