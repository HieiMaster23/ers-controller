# Pinos — EP4CE6E22C8 (PLACEHOLDERS)

Os pinos no arquivo `ers_ep4ce6.qsf` estão como **PIN_XX** de propósito.
**Não inventamos números de pino.** Lucas deve copiar do esquemático / manual da placa
(Cyclone IV EP4CE6 com VGA).

## Sinais a mapear

| Sinal RTL        | Direção | Notas |
|------------------|---------|--------|
| `clk_50`         | in      | Oscilador 50 MHz da placa |
| `rst_n`          | in      | Reset ativo-baixo (botão com pull-up típico) |
| `sw_start`       | in      | 0 = segura/reseta sequenciador; 1 = roda a volta |
| `sw_auto_manual` | in      | 1 = AUTO; 0 = MANUAL |
| `sw_deploy`      | in      | Deploy manual (só em MANUAL) |
| `led[3:0]`       | out     | 0=harvest, 1=deploy, 2=limit_hit, 3=full |
| `vga_hs`         | out     | HSYNC VGA |
| `vga_vs`         | out     | VSYNC VGA |
| `vga_r[3:0]`     | out     | Vermelho 4 bits |
| `vga_g[3:0]`     | out     | Verde 4 bits |
| `vga_b[3:0]`     | out     | Azul 4 bits |

## Como preencher

1. Abra o esquemático da sua placa e anote os pinos FPGA do conector VGA e do clock.
2. No Quartus: Assignments → Pin Planner, ou edite o `.qsf` trocando cada `PIN_XX`.
3. Confirme o padrão elétrico (geralmente 3.3-V LVTTL nestas placas).
4. Recompile após mapear.

## Clock de pixel

A v1 divide `clk_50` por 2 → **25.0 MHz** (VGA 640×480 tipicamente 25.175 MHz).
É suficientemente próximo para a maioria dos monitores. Um PLL a 25.175 MHz é opcional depois.
