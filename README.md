# ERS EP4CE6 — Prototipo FPGA (baseline-demo)

Simulador de volta com **Energy Recovery System** estilo Formula, em **VHDL-93**, alvo
**Altera Cyclone IV E EP4CE6E22C8**, Quartus II **13.0sp1**, ModelSim-Altera, stimuli em MATLAB/Octave.

**v1:** apenas **MGU-K + energy store**. Sem MGU-H. Matematica inteira.
Tick de planta lab aproximadamente **100 ms**; demo/feira usa **10 ms** em `ers_board_top`.
Placa: **RZ-EasyFPGA A2.2** com VGA **1 bit/cor** (sem framebuffer).

> Constantes inspiradas em F1 mas **unidades escaladas de prototipo — NAO sao oficiais FIA**.

Tag Git: **`baseline-demo`** — pinagem A2.2 + fit 36% LE + comando de gravacao abaixo.

---

## Layout

```
SimuladorERS/
  README.md
  rtl/           VHDL-93 (top de placa: ers_board_top)
  matlab/        gerador + MIF/CSV
  sim/           testbenches
  quartus/       .qpf .qsf PINOS.md RESOURCES.md
```

---

## Empacotamento da ROM (palavra 32 bits)

| Bits     | Campo     | Faixa tipica |
|----------|-----------|--------------|
| [7:0]    | speed     | 80..250      |
| [15:8]   | throttle  | 0..255       |
| [23:16]  | brake     | 0..255       |
| [27:24]  | sector    | 1..4         |
| [31:28]  | 0         | reservado    |

900 amostras x 0,1 s = **90 s** de volta sintetica **EXEMPLO** (nao e circuito real).

A ROM em `lap_rom.vhd` usa o array constante de `lap_rom_init.vhd` (mesmos numeros do MIF).

---

## Constantes / LSB (`ers_pkg.vhd`)

| Constante | Valor | Significado |
|-----------|------:|-------------|
| `C_LAP_LEN` | 900 | amostras por volta |
| `C_TICK_MS` | 100 | tick de planta alvo (ms) |
| `C_P_MAX` | 40 | potencia max. MGU-K (unidades/tick) |
| `C_E_HARVEST_LAP_MAX` | 1800 | orcamento harvest por volta |
| `C_E_DEPLOY_LAP_MAX` | 1800 | orcamento deploy por volta |
| `C_SOC_MAX` | 4000 | capacidade do store |
| `C_SOC_LOW` | 500 | limiar SOC para deploy em AUTO |
| `C_SOC_INIT` | 2000 | SOC inicial |
| `C_BRAKE_HARVEST_TH` | 80 | freio > limiar → harvest |
| `C_THROTTLE_DEPLOY_TH` | 180 | throttle ≥ limiar → deploy AUTO |

**LSB de energia:** 1 unidade de potencia x 1 tick = **1 unidade de SOC**.

---

## Cena VGA (640x480@60)

Gerada **por pixel** (sem framebuffer):

1. Fundo escuro
2. **Pista quadrada** (perimetro)
3. **Carro** posicionado por `track_motion` (throttle/freio integrais — nao ritmo fixo)
4. Barras de acelerador / freio / velocidade + SOC / HARVEST / DEPLOY / AUTO|MANUAL

Pixel clock: `clk_50 / 2` = **25.0 MHz**. Na A2.2, `ers_board_top` expoe 1 bit por cor (MSB).

---

## Controles

| Porta / KEY | Funcao |
|-------------|--------|
| KEY0 (`key_n[0]`, PIN_88) | Solto = roda a volta; pressionado = segura/zera |
| KEY1 (`key_n[1]`, PIN_89) | Solto = AUTO; pressionado = MANUAL |
| KEY2 (`key_n[2]`, PIN_90) | Em MANUAL, pressionado = pede DEPLOY |
| LEDs PIN_87..84 | harvest / deploy / limit / full (ativos em baixo) |

Harvest no freio ocorre em ambos os modos. Harvest e deploy **nunca** juntos (prioridade harvest).

Detalhe de pinos: `quartus/PINOS.md`.

---

## Gerar MIF / CSV

```bash
cd matlab
octave --no-gui gerar_volta_sintetica.m
# ou no MATLAB: run('gerar_volta_sintetica.m')
```

Apos regenerar o MIF, regenere `rtl/lap_rom_init.vhd` para sim/sintese alinharem.

---

## Simular (ModelSim-Altera)

Ordem sugerida (VHDL-93): `ers_pkg` → `lap_rom_init` → restante de `rtl/*.vhd` → `sim/tb_*.vhd`.

```tcl
vlib work
vcom -93 ../rtl/ers_pkg.vhd ../rtl/lap_rom_init.vhd ../rtl/lap_rom.vhd \
  ../rtl/lap_seq.vhd ../rtl/track_motion.vhd ../rtl/mgu_k.vhd ../rtl/energy_store.vhd \
  ../rtl/ers_ctrl.vhd ../rtl/vga_sync.vhd ../rtl/dash_vga.vhd ../rtl/dash_leds.vhd \
  ../rtl/ers_top.vhd ../rtl/ers_board_top.vhd ../sim/tb_ers_plant.vhd
vsim work.tb_ers_plant
run -all
```

---

## Compilar no Quartus II 13.0sp1

1. Abra `quartus/ers.qpf` (revisao `ers_ep4ce6`)
2. Device **EP4CE6E22C8**, top **`ers_board_top`**, pinagem em `quartus/PINOS.md`
3. Confirme nCEO liberado (`CYCLONEII_RESERVE_NCEO_AFTER_CONFIGURATION` = USE AS REGULAR IO)
4. Processing → Start Compilation
5. Artefato: `quartus/output_files/ers_ep4ce6.sof`

Recursos do fit congelado: `quartus/RESOURCES.md` (**2 289 / 6 272 LE = 36%**, 14 pinos, 0 bits de memoria).

---

## Gravar na placa (USB-Blaster)

```bat
cd /d C:\Users\Rafael\Documents\Projetos\SimuladorERS
quartus_pgm -c USB-Blaster -m jtag -o "p;quartus\output_files\ers_ep4ce6.sof"
```

Listar cabos: `quartus_pgm -l`. O `.sof` nao vai no git (`.gitignore`); regenere a partir desta tag.

---

## Caveats

- Pinagem A2.2 **congelada** (tag `baseline-demo`).
- **Sem MGU-H** nesta v1.
- **Sem PLL**: 25.0 MHz por divisao.
- **Sem framebuffer**; pista quadrada + `track_motion`.
- Modo feira: tick **10 ms** e auto-repeat.
