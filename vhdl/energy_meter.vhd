-- ============================================================================
-- Arquivo  : energy_meter.vhd
-- Autor    : Rafael
-- Data     : 2026-04-06
-- Descricao: Integrador de energia por volta. Acumula P * dt a cada ciclo
--            de clock quando deploy esta ativo. Reseta com lap_reset.
--
-- Escala de energia:
--   duty_cycle (0-65535) e proporcional a potencia de deploy:
--   P_deploy = (duty / 65535) * P_MAX_W
--   Saida em kJ com 8 bits fracionarios (Q8) em 24 bits.
--   Faixa: 0 a 65535.996 kJ (24 bits unsigned Q8)
--   Saturacao em 4000 kJ = 4 MJ -> 4000 * 256 = 1024000
--
-- Integracao (valores para os generics padrao, 120 kW @ 50 MHz):
--   dt = 1 / CLK_HZ = 20 ns
--   energy_per_clk = (duty / 65535) * 120000 W * 20e-9 s
--                  = duty * 3.662e-8 J = duty * 3.662e-11 kJ
--   Em Q8 (x256):   duty * 9.375e-9
--   O acumulador interno guarda a energia com 40 bits fracionarios extras
--   (escala 2^40), entao o incremento por ciclo e:
--     INTEG_SCALE = round(9.375e-9 * 2^40) = 10308   (erro < 0.001%)
--   Acumulador de 64 bits: bits [63:40] = energy_used (Q8 kJ).
--
--   Para testes com escala de tempo comprimida, CLK_HZ pode ser reduzido
--   (minimo 1000): com CLK_HZ = 1000 cada ciclo vale 1 ms de energia.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity energy_meter is
    generic (
        CLK_HZ  : positive := 50_000_000;  -- frequencia do clock (Hz), >= 1000
        P_MAX_W : positive := 120_000      -- potencia de deploy com duty = 65535 (W)
    );
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
    constant ENERGY_MAX : unsigned(23 downto 0) := to_unsigned(1024000, 24);

    -- Mesmo limite na escala do acumulador (Q8 kJ * 2^40)
    constant ACCUM_MAX  : unsigned(63 downto 0) :=
        ENERGY_MAX & to_unsigned(0, 40);

    -- Incremento por ciclo para duty = 1, na escala do acumulador:
    -- (P_MAX_W / 65535) [W] / CLK_HZ [s^-1] / 1000 [J->kJ] * 256 [Q8] * 2^40
    constant SCALE_REAL : real :=
        real(P_MAX_W) / 65535.0 / real(CLK_HZ) / 1000.0 * 256.0 * 2.0**40;
    constant INTEG_SCALE : unsigned(31 downto 0) :=
        to_unsigned(integer(SCALE_REAL), 32);

    -- ========================================================================
    -- Sinais internos
    -- ========================================================================
    -- Acumulador de 64 bits
    -- Bits [63:40] = energia em kJ Q8 (os 24 bits de saida)
    -- Bits [39:0]  = fracao extra para nao perder incrementos pequenos
    signal energy_accum : unsigned(63 downto 0);

    -- Produto intermediario: duty(16) * SCALE(32) = 48 bits
    signal increment    : unsigned(47 downto 0);

begin

    -- Calculo do incremento (combinacional)
    increment <= unsigned(duty_cycle) * INTEG_SCALE;

    -- ========================================================================
    -- Processo de integracao
    -- ========================================================================
    process(clk, rst_n)
        variable accum_new : unsigned(63 downto 0);
    begin
        if rst_n = '0' then
            energy_accum <= (others => '0');

        elsif rising_edge(clk) then
            if lap_reset = '1' then
                -- Reset de volta: zerar acumulador
                energy_accum <= (others => '0');

            elsif deploy_en = '1' then
                -- Integrar: acumular incremento
                accum_new := energy_accum + resize(increment, 64);

                -- Saturacao no maximo de energia (trava, nunca da a volta)
                if accum_new >= ACCUM_MAX then
                    energy_accum <= ACCUM_MAX;
                else
                    energy_accum <= accum_new;
                end if;
            end if;
            -- Se deploy_en = '0' e lap_reset = '0': manter valor atual
        end if;
    end process;

    -- ========================================================================
    -- Saida: 24 bits superiores do acumulador (kJ em Q8)
    -- ========================================================================
    energy_used <= std_logic_vector(energy_accum(63 downto 40));

end architecture rtl;
