# Pinos — RZ-EasyFPGA A2.2 / EP4CE6E22C8 (baseline-demo)

Pinagem **travada** no QSF `ers_ep4ce6.qsf` (fit 2026-09-16). I/O: **3.3-V LVTTL**.

> Obrigatório no Quartus:
> `CYCLONEII_RESERVE_NCEO_AFTER_CONFIGURATION = "USE AS REGULAR IO"`
> (e `RESERVE_NCEO_AFTER_CONFIGURATION`) para liberar **PIN_101** (nCEO) como VGA HS.

## Tabela de pinos (RTL ↔ FPGA)

| Sinal RTL  | Direção | FPGA pin   | Notas |
|------------|---------|------------|--------|
| `clk_50`   | in      | **PIN_23** | Oscilador 50 MHz |
| `rst_n`    | in      | **PIN_25** | Reset ativo-baixo |
| `key_n[0]` | in      | **PIN_88** | Solto = roda a volta; pressionado = segura/zera |
| `key_n[1]` | in      | **PIN_89** | Solto = AUTO; pressionado = MANUAL |
| `key_n[2]` | in      | **PIN_90** | Pressionado = pede DEPLOY (em MANUAL) |
| `led[0]`   | out     | **PIN_87** | Harvest (ativo-baixo na placa) |
| `led[1]`   | out     | **PIN_86** | Deploy |
| `led[2]`   | out     | **PIN_85** | Limit |
| `led[3]`   | out     | **PIN_84** | Full / carga |
| `vga_hs`   | out     | **PIN_101** | HSYNC (ex-nCEO) |
| `vga_vs`   | out     | **PIN_103** | VSYNC |
| `vga_r`    | out     | **PIN_106** | R 1-bit (MSB do canal 4:4:4) |
| `vga_g`    | out     | **PIN_105** | G 1-bit |
| `vga_b`    | out     | **PIN_104** | B 1-bit |

## Demo / feira

- Top de placa: `ers_board_top` (tick 10 ms, volta em loop).
- Polaridade KEY/LED tratada em `ers_board_top`.
- Fonte canônica: `quartus/ers_ep4ce6.qsf`.
