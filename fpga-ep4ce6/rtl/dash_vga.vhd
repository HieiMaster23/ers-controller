-------------------------------------------------------------------------------
-- dash_vga.vhd — Dashboard VGA sem framebuffer (gera cor por pixel x,y)
-- Cena: fundo escuro | oval a esquerda | carro | coluna SOC/HARVEST/DEPLOY/modo
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ers_pkg.all;

entity dash_vga is
  port (
    px_clk         : in  std_logic;
    rst_n          : in  std_logic;
    visible        : in  std_logic;
    x              : in  unsigned(9 downto 0);
    y              : in  unsigned(9 downto 0);
    sample_idx     : in  unsigned(9 downto 0);  -- 0..899
    soc            : in  unsigned(11 downto 0);
    harvest_active : in  std_logic;
    deploy_active  : in  std_logic;
    mode_auto      : in  std_logic;
    vga_r          : out std_logic_vector(3 downto 0);
    vga_g          : out std_logic_vector(3 downto 0);
    vga_b          : out std_logic_vector(3 downto 0)
  );
end entity dash_vga;

architecture rtl of dash_vga is
  component sin_lut is
    port (
      theta : in  unsigned(7 downto 0);
      sine  : out unsigned(7 downto 0)
    );
  end component;

  -- Centro e raios da elipse (inteiros)
  constant CX : integer := 220;
  constant CY : integer := 240;
  constant RX : integer := 160;   -- semi-eixo X
  constant RY : integer := 110;   -- semi-eixo Y
  -- Anel: razao tipica ~0.88 (inner) e 1.00 (outer) via limites de "r2"
  -- Usamos teste: inner_scale^2 * denom <= nx^2*RY^2 + ny^2*RX^2 <= outer
  -- Simplificado: pontua se dist_elliptical entre INNER e OUTER
  constant INNER_NUM : integer := 78;  -- ~0.88 * 88 approx via scaled compare
  -- Comparacao: val = nx*nx*RY*RY + ny*ny*RX*RX
  -- outer: RX^2 * RY^2 ; inner: (RX*inner/100)^2 * RY^2  -> use fractions
  -- val_outer = RX*RX*RY*RY
  -- val_inner = (RX*88/100)*(RX*88/100)*RY*RY
  constant RX2 : integer := RX * RX;          -- 25600
  constant RY2 : integer := RY * RY;          -- 12100
  constant OUTER : integer := RX2 * RY2;      -- grande
  constant RXI   : integer := (RX * 88) / 100; -- 140
  constant RXI2  : integer := RXI * RXI;
  constant INNER : integer := RXI2 * RY2;

  signal theta     : unsigned(7 downto 0);
  signal sin_v     : unsigned(7 downto 0);
  signal cos_v     : unsigned(7 downto 0);
  signal theta_c   : unsigned(7 downto 0);

  signal r_r : std_logic_vector(3 downto 0) := (others => '0');
  signal r_g : std_logic_vector(3 downto 0) := (others => '0');
  signal r_b : std_logic_vector(3 downto 0) := (others => '0');
begin
  -- Angulo: idx 0..899 -> 0..255 approx (idx * 256 / 900)
  -- process combinational via concurrent integers
  theta   <= to_unsigned((to_integer(sample_idx) * 256) / 900, 8);
  theta_c <= theta + to_unsigned(64, 8);

  u_sin : sin_lut port map (theta => theta,   sine => sin_v);
  u_cos : sin_lut port map (theta => theta_c, sine => cos_v);

  vga_r <= r_r;
  vga_g <= r_g;
  vga_b <= r_b;

  process (px_clk)
    variable vx, vy   : integer;
    variable nx, ny   : integer;
    variable val      : integer;
    variable on_track : boolean;
    variable car_x    : integer;
    variable car_y    : integer;
    variable soc_h    : integer;
    variable pix_r, pix_g, pix_b : integer;
  begin
    if rising_edge(px_clk) then
      if rst_n = '0' then
        r_r <= (others => '0');
        r_g <= (others => '0');
        r_b <= (others => '0');
      else
        pix_r := 0; pix_g := 0; pix_b := 0;
        if visible = '1' then
          vx := to_integer(x);
          vy := to_integer(y);

          -- fundo escuro
          pix_r := 1; pix_g := 1; pix_b := 2;

          -- posicao do carro no oval (sin/cos centrados em 128)
          car_x := CX + ((to_integer(cos_v) - 128) * RX) / 128;
          car_y := CY + ((to_integer(sin_v) - 128) * RY) / 128;

          -- elipse anel (poucos multiplicadores 18x18)
          nx := vx - CX;
          ny := vy - CY;
          -- val = nx^2 * RY2 + ny^2 * RX2
          val := (nx * nx) * RY2 + (ny * ny) * RX2;
          on_track := (val >= INNER) and (val <= OUTER);

          if on_track then
            pix_r := 10; pix_g := 10; pix_b := 10;  -- cinza claro
          end if;

          -- carro ~8x8 amarelo/laranja
          if (vx >= car_x - 4) and (vx <= car_x + 4) and
             (vy >= car_y - 4) and (vy <= car_y + 4) then
            pix_r := 15; pix_g := 12; pix_b := 0;
          end if;

          -- Coluna direita: painel
          if vx >= 500 then
            -- fundo do painel
            pix_r := 2; pix_g := 2; pix_b := 3;

            -- barra SOC vertical (x=520..540, y=40..440), altura prop. a SOC
            soc_h := (to_integer(soc) * 400) / C_SOC_MAX;
            if soc_h > 400 then
              soc_h := 400;
            end if;
            if vx >= 520 and vx <= 540 then
              if vy >= (440 - soc_h) and vy <= 440 then
                pix_r := 2; pix_g := 14; pix_b := 2;  -- verde
              elsif vy >= 40 and vy <= 440 then
                pix_r := 1; pix_g := 3; pix_b := 1;   -- trilho dim
              end if;
            end if;

            -- bloco HARVEST (y=40..80, x=560..620)
            if vx >= 560 and vx <= 620 and vy >= 40 and vy <= 80 then
              if harvest_active = '1' then
                pix_r := 2; pix_g := 15; pix_b := 2;
              else
                pix_r := 1; pix_g := 4; pix_b := 1;
              end if;
            end if;

            -- bloco DEPLOY (y=100..140, x=560..620)
            if vx >= 560 and vx <= 620 and vy >= 100 and vy <= 140 then
              if deploy_active = '1' then
                pix_r := 15; pix_g := 6; pix_b := 0;
              else
                pix_r := 4; pix_g := 2; pix_b := 1;
              end if;
            end if;

            -- AUTO / MANUAL (y=160..180)
            if vx >= 560 and vx <= 620 and vy >= 160 and vy <= 180 then
              if mode_auto = '1' then
                pix_r := 2; pix_g := 8; pix_b := 14;  -- azul = AUTO
              else
                pix_r := 12; pix_g := 10; pix_b := 2; -- amarelo = MANUAL
              end if;
            end if;
          end if;
        end if;

        r_r <= std_logic_vector(to_unsigned(pix_r, 4));
        r_g <= std_logic_vector(to_unsigned(pix_g, 4));
        r_b <= std_logic_vector(to_unsigned(pix_b, 4));
      end if;
    end if;
  end process;
end architecture rtl;
