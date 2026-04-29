-- ============================================================================
-- Arquivo  : pi_controller.vhd
-- Autor    : Rafael
-- Data     : 2026-04-06
-- Descricao: Controlador PI digital em ponto fixo Q16.16.
--            Regula o duty cycle do PWM do MGU-K com base no erro entre
--            setpoint e valor medido. Anti-windup por clamping no integrador.
--
-- Formato Q16.16: 16 bits inteiros + 16 bits fracionarios = 32 bits signed.
--   Faixa: -32768.0 a +32767.99998 (resolucao ~1.5e-5)
--   Multiplicacao gera 64 bits; truncamos para 32 apos shift.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pi_controller is
    generic (
        KP      : integer := 1024;   -- ganho proporcional em Q16 (1024 = 0.015625)
        KI      : integer := 64;     -- ganho integral em Q16 (64 = 0.000977)
        OUT_MAX : integer := 65535;  -- duty cycle maximo (16 bits)
        OUT_MIN : integer := 0       -- duty cycle minimo
    );
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;
        enable    : in  std_logic;                      -- habilita o controlador
        setpoint  : in  std_logic_vector(15 downto 0);  -- referencia (unsigned)
        measured  : in  std_logic_vector(15 downto 0);  -- valor medido (unsigned)
        duty_out  : out std_logic_vector(15 downto 0)   -- duty cycle (unsigned)
    );
end entity pi_controller;

architecture rtl of pi_controller is

    -- ========================================================================
    -- Constantes Q16
    -- ========================================================================
    -- Limites do integrador para anti-windup (em Q16)
    -- Limite: OUT_MAX << 16 para manter na escala Q16 antes do shift final
    constant INTEG_MAX : signed(31 downto 0) :=
        to_signed(OUT_MAX * 256, 32);  -- margem ampla para o integrador
    constant INTEG_MIN : signed(31 downto 0) :=
        to_signed(OUT_MIN, 32);

    -- ========================================================================
    -- Sinais internos
    -- ========================================================================
    -- Erro = setpoint - measured (signed 17 bits para nao ter overflow)
    signal error_val   : signed(16 downto 0);

    -- Termos P e I em Q16 (32 bits signed)
    signal p_term      : signed(31 downto 0);
    signal i_accum     : signed(31 downto 0);  -- acumulador integral
    signal i_term      : signed(31 downto 0);
    signal pi_sum      : signed(31 downto 0);

    -- Saida saturada
    signal output_sat  : integer range 0 to 65535;

begin

    -- ========================================================================
    -- Calculo do erro (combinacional)
    -- Extensao de sinal: unsigned 16 bits -> signed 17 bits
    -- ========================================================================
    error_val <= signed('0' & setpoint) - signed('0' & measured);

    -- ========================================================================
    -- Processo principal: calculo PI sincrono
    -- ========================================================================
    process(clk, rst_n)
        variable p_calc    : signed(31 downto 0);
        variable i_new     : signed(31 downto 0);
        variable sum_calc  : signed(31 downto 0);
        variable out_int   : integer;
    begin
        if rst_n = '0' then
            i_accum    <= (others => '0');
            p_term     <= (others => '0');
            i_term     <= (others => '0');
            pi_sum     <= (others => '0');
            output_sat <= 0;

        elsif rising_edge(clk) then
            if enable = '1' then
                -- Termo proporcional: P = KP * error
                -- error_val e 17 bits, KP cabe em 16 bits -> resultado 33 bits
                -- Usamos resize para 32 bits (seguro pois KP e error sao pequenos)
                p_calc := resize(error_val * to_signed(KP, 16), 32);
                p_term <= p_calc;

                -- Termo integral: I_accum += KI * error
                i_new := i_accum + resize(error_val * to_signed(KI, 16), 32);

                -- Anti-windup: clamping do acumulador
                if i_new > INTEG_MAX then
                    i_accum <= INTEG_MAX;
                elsif i_new < INTEG_MIN then
                    i_accum <= INTEG_MIN;
                else
                    i_accum <= i_new;
                end if;

                i_term <= i_accum;

                -- Soma P + I
                sum_calc := p_calc + i_accum;
                pi_sum   <= sum_calc;

                -- Converter de Q16 para inteiro: shift right 16
                -- (dividir por 65536 para remover a fracao)
                out_int := to_integer(shift_right(sum_calc, 16));

                -- Saturacao da saida
                if out_int > OUT_MAX then
                    output_sat <= OUT_MAX;
                elsif out_int < OUT_MIN then
                    output_sat <= 0;
                else
                    output_sat <= out_int;
                end if;

            else
                -- Desabilitado: zerar saida, manter integrador
                output_sat <= 0;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- Saida
    -- ========================================================================
    duty_out <= std_logic_vector(to_unsigned(output_sat, 16));

end architecture rtl;
