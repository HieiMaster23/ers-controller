-- ============================================================================
-- Arquivo  : energy_meter.vhd
-- Autor    : Rafael
-- Data     : 2026-04-06
-- Descricao: Integrador de energia por volta. Acumula P * dt a cada ciclo
--            de clock quando deploy esta ativo. Reseta com lap_reset.
--
-- Escala de energia:
--   duty_cycle (0-65535) e proporcional a potencia de deploy.
--   P_deploy = duty_cycle * P_MAX_SCALE (constante de escala)
--   Usamos unidade de kJ com 8 bits fracionarios (Q8) em 24 bits.
--   Faixa: 0 a 65535.996 kJ (24 bits unsigned Q8)
--   Saturacao em 4000 kJ = 4 MJ -> 4000 * 256 = 1024000
--
-- Integracao:
--   dt = 1/50MHz = 20 ns = 20e-9 s
--   A cada ciclo: energy += P_instantanea * dt
--   P_instantanea = (duty / 65535) * 120000 W = duty * 1.831 W
--   energy_increment = P * dt = duty * 1.831 * 20e-9 = duty * 3.662e-5 J
--                    = duty * 3.662e-8 kJ
--   Em Q8: duty * 3.662e-8 * 256 = duty * 9.375e-6
--   Aproximado como: duty >> 17 (divide por 131072 ~ 1/106496)
--   Mais preciso: usamos um acumulador fracionario de 40 bits internamente
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity energy_meter is
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        deploy_en   : in  std_logic;                      -- '1' quando esta em deploy
        duty_cycle  : in  std_logic_vector(15 downto 0);  -- duty do PWM (0-65535)
        lap_reset   : in  std_logic;                      -- pulso de 1 ciclo para reset de volta
        energy_used : out std_logic_vector(23 downto 0)   -- energia acumulada (kJ, Q8)
    );
end entity energy_meter;

architecture rtl of energy_meter is

    -- ========================================================================
    -- Constantes
    -- ========================================================================
    -- Energia maxima por volta: 4 MJ = 4000 kJ, em Q8 = 1024000
    constant ENERGY_MAX : unsigned(39 downto 0) :=
        to_unsigned(1024000, 40);

    -- Fator de escala para integracao:
    -- P = (duty / 65535) * 120000 W
    -- energy_per_clk = P * 20e-9 s = duty * 120000/65535 * 20e-9 J
    --                = duty * 3.662e-5 J = duty * 3.662e-8 kJ
    -- Em Q8 (x256): duty * 9.375e-6
    -- Em acumulador de 40 bits para precisao, usamos shift+add:
    -- 9.375e-6 ~= 1/106667 ~= acumular em bits altos
    -- Simplificacao: usamos multiplicacao por constante pequena e shift
    -- SCALE = round(9.375e-6 * 2^24) = round(157.286) = 157
    constant INTEG_SCALE : unsigned(7 downto 0) := to_unsigned(157, 8);

    -- ========================================================================
    -- Sinais internos
    -- ========================================================================
    -- Acumulador fracionario de 40 bits para manter precisao
    -- Bits [39:24] = parte inteira em Q8 (os 24 bits de saida)
    -- Bits [23:0]  = parte fracionaria (acumulacao)
    signal energy_accum : unsigned(39 downto 0);

    -- Produto intermediario: duty(16) * SCALE(8) = 24 bits
    signal increment    : unsigned(23 downto 0);

begin

    -- Calculo do incremento (combinacional)
    -- duty_cycle * INTEG_SCALE, resultado em 24 bits
    increment <= unsigned(duty_cycle) * INTEG_SCALE;

    -- ========================================================================
    -- Processo de integracao
    -- ========================================================================
    process(clk, rst_n)
        variable accum_new : unsigned(39 downto 0);
    begin
        if rst_n = '0' then
            energy_accum <= (others => '0');

        elsif rising_edge(clk) then
            if lap_reset = '1' then
                -- Reset de volta: zerar acumulador
                energy_accum <= (others => '0');

            elsif deploy_en = '1' then
                -- Integrar: acumular incremento
                accum_new := energy_accum + resize(increment, 40);

                -- Saturacao no maximo de energia
                if accum_new(39 downto 24) > ENERGY_MAX(39 downto 24) then
                    -- Travar no valor maximo (24 bits superiores = ENERGY_MAX)
                    energy_accum(39 downto 24) <= ENERGY_MAX(39 downto 24);
                    energy_accum(23 downto 0)  <= (others => '0');
                else
                    energy_accum <= accum_new;
                end if;
            end if;
            -- Se deploy_en = '0' e lap_reset = '0': manter valor atual
        end if;
    end process;

    -- ========================================================================
    -- Saida: 24 bits superiores do acumulador (parte inteira em Q8)
    -- ========================================================================
    energy_used <= std_logic_vector(energy_accum(39 downto 16));

end architecture rtl;
