# ERS EP4CE6 — Prototipo FPGA (v1, sem MGU-H)

Simulador de volta com **Energy Recovery System** estilo Formula, em **VHDL-93**, alvo
**Altera Cyclone IV E EP4CE6E22C8**, Quartus II **13.0sp1**, ModelSim-Altera, stimuli em MATLAB/Octave.

**v1:** apenas **MGU-K + energy store**. Sem MGU-H. Matemática inteira. Tick de planta ≈ **100 ms**.
Placa tem VGA; **sem framebuffer** (gerar cor no scan a partir de x,y) por causa do limite
(~6272 LEs / 270 kbit RAM).

> Constantes inspiradas em F1 mas **unidades escaladas de prototipo — NÃO são oficiais FIA**.

---

## Layout neste repositório

```
fpga-ep4ce6/
  README.md
  rtl/           VHDL-93
  matlab/        gerador + MIF/CSV
  sim/           testbenches
  quartus/       .qpf .qsf PINOS.md
```

A árvore antiga de controlador Simulink/ModelSim (`vhdl/`, `simulink/`, `docs/`, `testbench/`, `scripts/`) permanece na raiz do repositório; este diretório é o alvo de placa.

---

## Empacotamento da ROM (palavra 32 bits)

| Bits     | Campo     | Faixa típica |
|----------|-----------|--------------|
| [7:0]    | speed     | 80..250      |
| [15:8]   | throttle  | 0..255       |
| [23:16]  | brake     | 0..255       |
| [27:24]  | sector    | 1..4         |
| [31:28]  | 0         | reservado    |

900 amostras × 0,1 s = **90 s** de volta sintética **EXEMPLO** (não é circuito real).

A ROM em `lap_rom.vhd` usa o array constante de `lap_rom_init.vhd` (mesmos números do MIF),
para sim e síntese baterem **sem MegaWizard**. O MIF em `matlab/volta_sintetica.mif` fica
disponível se quiser `altsyncram` + `INIT_FILE` depois.

---

## Constantes / LSB (`ers_pkg.vhd`)

| Constante | Valor | Significado |
|-----------|------:|-------------|
| `C_LAP_LEN` | 900 | amostras por volta |
| `C_TICK_MS` | 100 | tick de planta alvo (ms) |
| `C_P_MAX` | 40 | potência máx. MGU-K (unidades/tick) |
| `C_E_HARVEST_LAP_MAX` | 1800 | orçamento harvest por volta |
| `C_E_DEPLOY_LAP_MAX` | 1800 | orçamento deploy por volta |
| `C_SOC_MAX` | 4000 | capacidade do store |
| `C_SOC_LOW` | 500 | limiar SOC para deploy em AUTO |
| `C_SOC_INIT` | 2000 | SOC inicial |
| `C_BRAKE_HARVEST_TH` | 80 | freio > limiar → harvest |
| `C_THROTTLE_DEPLOY_TH` | 180 | throttle ≥ limiar → deploy AUTO |

**LSB de energia:** 1 unidade de potência × 1 tick = **1 unidade de SOC**.
Em hardware, `g_tick_div = f_clk / 10` (ex.: 50 MHz → 5_000_000) para tick de 100 ms.

---

## Cena VGA (640×480@60, RGB 4:4:4)

Gerada **por pixel** (sem framebuffer):

1. Fundo escuro
2. **Anel oval** (elipse) à esquerda/centro — cinza claro
3. **Carro** retângulo ~8×8 amarelo/laranja na posição angular do `sample_idx`
4. Coluna direita: barra vertical **SOC** (verde), blocos **HARVEST** (verde ativo / dim),
   **DEPLOY** (laranja ativo / dim), indicador **AUTO** (azul) / **MANUAL** (amarelo)

Pixel clock: `clk_50 / 2` = **25.0 MHz** (próximo de 25.175; PLL opcional depois). Timing
padrão 800×525 (H: 16/96/48, V: 10/2/33).

---

## Controles

| Porta | Função |
|-------|--------|
| `sw_start` | 0 = hold/reset do sequenciador; 1 = roda |
| `sw_auto_manual` | 1 = AUTO (deploy no throttle alto se SOC > SOC_LOW); 0 = MANUAL |
| `sw_deploy` | em MANUAL, pede deploy enquanto =1 |
| `led[0..3]` | harvest / deploy / limit_hit / full |

Harvest no freio ocorre em ambos os modos. Harvest e deploy **nunca** juntos (prioridade harvest).

---

## Gerar MIF / CSV

### MATLAB / Octave

```bash
cd matlab
octave --no-gui gerar_volta_sintetica.m
# ou no MATLAB: run('gerar_volta_sintetica.m')
```

Gera `volta_sintetica.mif` e `volta_sintetica.csv` no diretório atual.

### Python (equivalente — usado neste repositório na box)

Se não houver MATLAB/Octave, rode um gerador Python que emite os **mesmos** números e
também regenera `rtl/lap_rom_init.vhd`. Os arquivos já commitados/gerados sob `matlab/` e
`rtl/lap_rom_init.vhd` estão prontos.

Após regenerar o MIF, regenere `lap_rom_init.vhd` para sim/síntese continuarem alinhados.

---

## Simular (ModelSim-Altera)

Ordem sugerida de compilação (VHDL-93):

1. `rtl/ers_pkg.vhd`
2. `rtl/lap_rom_init.vhd`
3. restante de `rtl/*.vhd`
4. `sim/tb_ers.vhd` e/ou `sim/tb_ers_plant.vhd`

```tcl
# Exemplo ModelSim
vlib work
vcom -93 ../rtl/ers_pkg.vhd ../rtl/lap_rom_init.vhd ../rtl/lap_rom.vhd \
  ../rtl/lap_seq.vhd ../rtl/mgu_k.vhd ../rtl/energy_store.vhd ../rtl/ers_ctrl.vhd \
  ../rtl/sin_lut.vhd ../rtl/vga_sync.vhd ../rtl/dash_vga.vhd ../rtl/dash_leds.vhd \
  ../rtl/ers_top.vhd ../sim/tb_ers_plant.vhd
vsim work.tb_ers_plant
run -all
```

O TB usa `g_tick_div => 1` (1 ciclo = 1 tick) para uma volta rápida.

---

## Compilar no Quartus II 13.0sp1

1. Abra `quartus/ers.qpf`
2. **Preencha os pinos** em `ers_ep4ce6.qsf` (hoje são **PIN_XX** — ver `quartus/PINOS.md`)
3. Processing → Start Compilation
4. Programe o `.sof` na placa e ligue um monitor VGA

Device: **EP4CE6E22C8**, Family **Cyclone IV E**, top **ers_top**.

---

## Caveats

- **Pinos do QSF são PLACEHOLDERS** — nunca inventados; preencha pelo esquemático.
- **Sem MGU-H** nesta v1.
- **Sem PLL**: 25.0 MHz por divisão; PLL 25.175 MHz opcional.
- **Sem framebuffer**; elipse usa multiplicações inteiras (DSP 18×18 da EP4CE6 ajudam).
- ROM = array VHDL (não depende de IP); MIF é referência / caminho futuro `INIT_FILE`.
