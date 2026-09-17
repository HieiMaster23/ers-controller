-------------------------------------------------------------------------------
-- dash_vga.vhd ? Pista QUADRADA + carro pela posicao/velocidade real
-- Mostra tambem barras de acelerador e freio.
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
    track_pos      : in  unsigned(9 downto 0);  -- 0..1023 ao longo do quadrado
    speed          : in  unsigned(7 downto 0);
    throttle       : in  unsigned(7 downto 0);
    brake          : in  unsigned(7 downto 0);
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
  -- Quadrado da pista (anel)
  constant L : integer := 70;
  constant T : integer := 50;
  constant RGT : integer := 370;
  constant B : integer := 390;
  constant TH : integer := 14;           -- espessura do anel
  constant SIDE : integer := 256;        -- 4*256 = 1024 = perimetro logico

  signal r_r : std_logic_vector(3 downto 0) := (others => '0');
  signal r_g : std_logic_vector(3 downto 0) := (others => '0');
  signal r_b : std_logic_vector(3 downto 0) := (others => '0');
begin
  vga_r <= r_r;
  vga_g <= r_g;
  vga_b <= r_b;

  process (px_clk)
    variable vx, vy : integer;
    variable p      : integer;
    variable seg    : integer;
    variable off    : integer;
    variable car_x  : integer;
    variable car_y  : integer;
    variable on_trk : boolean;
    variable soc_h  : integer;
    variable thr_h  : integer;
    variable brk_h  : integer;
    variable pix_r, pix_g, pix_b : integer;
    variable spd_h  : integer;
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

          -- fundo
          pix_r := 1; pix_g := 1; pix_b := 2;

          -- anel quadrado (borda externa - interna)
          on_trk := false;
          if vx >= L and vx <= RGT and vy >= T and vy <= B then
            if vx < L + TH or vx > RGT - TH or vy < T + TH or vy > B - TH then
              on_trk := true;
            end if;
          end if;
          if on_trk then
            pix_r := 10; pix_g := 10; pix_b := 10;
          end if;

          -- posicao do carro no perimetro 0..1023
          p := to_integer(track_pos);
          if p > 1023 then
            p := 1023;
          end if;
          seg := p / SIDE;
          off := p - seg * SIDE;
          -- mapeia off 0..255 para o comprimento do lado em pixels
          case seg is
            when 0 =>  -- topo, esquerda -> direita
              car_x := L + (off * (RGT - L)) / SIDE;
              car_y := T + TH / 2;
            when 1 =>  -- direita, cima -> baixo
              car_x := RGT - TH / 2;
              car_y := T + (off * (B - T)) / SIDE;
            when 2 =>  -- base, direita -> esquerda
              car_x := RGT - (off * (RGT - L)) / SIDE;
              car_y := B - TH / 2;
            when others =>  -- esquerda, baixo -> cima
              car_x := L + TH / 2;
              car_y := B - (off * (B - T)) / SIDE;
          end case;

          if (vx >= car_x - 5) and (vx <= car_x + 5) and
             (vy >= car_y - 5) and (vy <= car_y + 5) then
            pix_r := 15; pix_g := 12; pix_b := 0;
          end if;

          -- painel direito
          if vx >= 500 then
            pix_r := 2; pix_g := 2; pix_b := 3;

            -- barra SOC
            soc_h := (to_integer(soc) * 400) / C_SOC_MAX;
            if soc_h > 400 then soc_h := 400; end if;
            if vx >= 520 and vx <= 540 then
              if vy >= (440 - soc_h) and vy <= 440 then
                pix_r := 2; pix_g := 14; pix_b := 2;
              elsif vy >= 40 and vy <= 440 then
                pix_r := 1; pix_g := 3; pix_b := 1;
              end if;
            end if;

            -- barra velocidade (ao lado do SOC)
            spd_h := (to_integer(speed) * 400) / 180;
            if spd_h > 400 then spd_h := 400; end if;
            if vx >= 548 and vx <= 560 then
              if vy >= (440 - spd_h) and vy <= 440 then
                pix_r := 4; pix_g := 10; pix_b := 15;
              elsif vy >= 40 and vy <= 440 then
                pix_r := 1; pix_g := 2; pix_b := 3;
              end if;
            end if;

            -- HARVEST / DEPLOY / modo
            if vx >= 570 and vx <= 630 and vy >= 40 and vy <= 80 then
              if harvest_active = '1' then
                pix_r := 2; pix_g := 15; pix_b := 2;
              else
                pix_r := 1; pix_g := 4; pix_b := 1;
              end if;
            end if;
            if vx >= 570 and vx <= 630 and vy >= 100 and vy <= 140 then
              if deploy_active = '1' then
                pix_r := 15; pix_g := 6; pix_b := 0;
              else
                pix_r := 4; pix_g := 2; pix_b := 1;
              end if;
            end if;
            if vx >= 570 and vx <= 630 and vy >= 160 and vy <= 180 then
              if mode_auto = '1' then
                pix_r := 2; pix_g := 8; pix_b := 14;
              else
                pix_r := 12; pix_g := 10; pix_b := 2;
              end if;
            end if;

            -- barras horizontais: acelerador (verde) e freio (vermelho)
            thr_h := (to_integer(throttle) * 120) / 255;
            brk_h := (to_integer(brake) * 120) / 255;
            if vy >= 220 and vy <= 236 then
              if vx >= 570 and vx < 570 + thr_h then
                pix_r := 2; pix_g := 14; pix_b := 2;
              elsif vx >= 570 and vx <= 690 then
                pix_r := 1; pix_g := 3; pix_b := 1;
              end if;
            end if;
            if vy >= 250 and vy <= 266 then
              if vx >= 570 and vx < 570 + brk_h then
                pix_r := 15; pix_g := 2; pix_b := 2;
              elsif vx >= 570 and vx <= 690 then
                pix_r := 3; pix_g := 1; pix_b := 1;
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
