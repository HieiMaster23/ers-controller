# SCALE — contrato numérico dos estímulos ERS EP4CE6

Contrato da pasta canônica `fpga-ep4ce6/stim/` para o protótipo FPGA
(Cyclone IV E **EP4CE6**, Quartus II **13.0sp1**, ModelSim-Altera).
Valores inteiros / ponto fixo; sem ponto flutuante no hardware.

**Perfis neste diretório são EXEMPLO** (volta sintética, não telemetria de
circuito real), salvo marcação explícita em contrário no próprio arquivo.

O gerador MATLAB/Octave vive em `fpga-ep4ce6/matlab/`. A ROM de síntese hoje
é o array VHDL `rtl/lap_rom_init.vhd` (mesmos números). Este arquivo define o
empacotamento e os formatos que qualquer fonte — gerador, ROM ou testbench —
deve respeitar.

---

## Aviso EXEMPLO

| Marcação | Significado |
|----------|-------------|
| **EXEMPLO** (padrão) | Perfil sintético para bancada. Não é um circuito real. |
| Outra (só se o arquivo disser) | Ainda não há perfil de pista real neste repositório. |

`volta_sintetica.*` é **EXEMPLO**. Não inventar telemetria de pista aqui.

---

## Tempo e profundidade

| Símbolo | Valor | Notas |
|---------|------:|-------|
| `Ts` | **0,1 s** | Período de amostragem (= tick de planta, `C_TICK_MS = 100`) |
| `N` | **900** | Amostras por volta (`C_LAP_LEN`) |
| Duração | **90 s** | `N × Ts` |
| `DEPTH` | 900 | MIF / profundidade da ROM |
| `WIDTH` | 32 | bits por palavra |
| `ADDRESS_RADIX` | `DEC` | endereço 0 .. 899 |
| `DATA_RADIX` | `HEX` | palavra 32 bits em 8 dígitos hex |

Endereço `i` (0-based) corresponde ao instante `t = i × Ts`.

---

## Empacotamento da palavra 32 bits

Uma amostra = uma palavra. Bits **[31:28] devem ser escritos 0**.

```
 31   28 27  24 23        16 15         8 7          0
 +------+------+------------+------------+------------+
 |  0   |sector|   brake    |  throttle  |   speed    |
 | 4b   |  4b  |    8b      |    8b      |    8b      |
 +------+------+------------+------------+------------+
```

| Bits | Campo | Largura | Faixa útil | LSB | Saturação no gerador |
|------|--------|--------:|------------|-----|----------------------|
| [7:0] | `speed` | 8 | 0 .. 255 (típico 80 .. 250 neste EXEMPLO) | 1 unidade de protótipo / bit (não é km/h FIA) | clamp **0 .. 255** |
| [15:8] | `throttle` | 8 | 0 .. 255 | 1 / 255 do curso (0 = solto, 255 = máximo) | clamp **0 .. 255** |
| [23:16] | `brake` | 8 | 0 .. 255 | 1 / 255 do curso (0 = solto, 255 = máximo) | clamp **0 .. 255** |
| [27:24] | `sector` | 4 | **1 .. 4** neste EXEMPLO | 1 setor / bit | nibble cabe **0 .. 15**; o gerador satura **1 .. 15** |
| [31:28] | reservado | 4 | **0** | — | deve ser **0** (não usar para dados) |

Decodificação (igual a `ers_pkg.vhd`):

- `speed    = word(7 downto 0)`
- `throttle = word(15 downto 8)`
- `brake    = word(23 downto 16)`
- `sector   = word(27 downto 24)`

Montagem (inteiros não negativos):

```
word = (sector << 24) | (brake << 16) | (throttle << 8) | speed
```

Exemplo (amostra 0 de `volta_sintetica`): `0105F0B4`

- sector = `0x1` = 1
- brake = `0x05` = 5
- throttle = `0xF0` = 240
- speed = `0xB4` = 180

Não há mapeamento oficial para km/h, newton ou percentagem FIA neste contrato.
São contagens de protótipo, amigáveis a VHDL unsigned.

---

## Formatos de arquivo

Todos descrevem as **mesmas** 900 palavras, na mesma ordem. Nomes:
`volta_sintetica.mif` / `.hex` / `.txt`.

### `.mif` — Memory Initialization File (Quartus ROM)

Formato nativo Quartus II (`altsyncram` `INIT_FILE`, Memory Editor).

Cabeçalho obrigatório deste contrato:

```
DEPTH = 900;
WIDTH = 32;
ADDRESS_RADIX = DEC;
DATA_RADIX = HEX;
CONTENT
BEGIN
```

Cada linha de dados: `AAAA : XXXXXXXX;` com endereço decimal (largura 4 no
gerador, ex. `   0 : 0105F0B4;`) e palavra hex de 8 dígitos, **maiúsculos**.
Fecha com `END;`.

Comentários `--` no topo são permitidos.

### `.hex` — Intel HEX-32 (Quartus `INIT_FILE` / modelo `altsyncram` no ModelSim-Altera)

**Não** é o formato de `$readmemh`. É Intel HEX clássico (`:` no início da linha),
o mesmo estilo que o Quartus II 13.0sp1 exporta/consome como `.hex` de memória.

Este repositório escolheu Intel HEX para `.hex` porque:

1. Quartus `INIT_FILE` aceita `.mif` **ou** Intel HEX.
2. O modelo de simulação `altsyncram` do ModelSim-Altera lê Intel HEX / MIF,
   não a lista crua de `$readmemh`.

Regras deste contrato:

| Campo | Valor |
|-------|--------|
| Record de dados | tipo `00`, **4 bytes** (= 1 palavra de 32 bits) |
| Endereço | **em bytes**: `addr = índice_da_palavra × 4` |
| Ordem dos bytes | **MSB primeiro** (os 8 dígitos do MIF, da esquerda para a direita) |
| Extended Linear Address | desnecessário (3600 bytes < 64 KiB) |
| EOF | `:00000001FF` |

Exemplo da palavra 0 (`0105F0B4`) no endereço byte 0:

```
:040000000105F0B452
```

Checksum = complemento de dois da soma de todos os bytes do record
(comprimento, endereço, tipo, dados), 8 bits.

Para carregar no ModelSim **sem** IP Altera, use `.txt` + `$readmemh` (abaixo),
não este `.hex`.

### `.txt` — uma palavra hex por linha (`$readmemh` / VHDL textio)

Formato que **testbenches** ModelSim-Altera em Verilog costumam ler com
`$readmemh("volta_sintetica.txt")`, e que VHDL lê com `textio` (`hread`).

| Regra | Valor neste contrato |
|-------|----------------------|
| Uma palavra por linha | 8 dígitos hex **maiúsculos**, sem prefixo `0x` |
| Endereço | **omitido** (sem `@aaaa`) — endereço = número da linha, 0-based |
| Linhas | exatamente **900**, LF (`\n`), sem linha em branco no meio |
| Comentários | não usar |

```
0105F0B4
0105F0B4
0105F0B5
…
```

`$readmemh` interpreta cada token como uma palavra da memória; com WIDTH=32
no DUT, cada linha preenche um endereço. Não misturar com Intel HEX: uma linha
que começa com `:` **não** é `$readmemh` válido.

---

## Convenção de caminhos

| Pasta | Papel |
|-------|--------|
| **`fpga-ep4ce6/stim/`** | **Canônica.** Contrato (`SCALE.md`) + `.mif` / `.hex` / `.txt` que RTL, Quartus e TB devem referenciar. |
| `fpga-ep4ce6/matlab/` | Workspace do gerador: `gerar_volta_sintetica.m`, CSV de inspeção, e cópia do `.mif`. |

O script `matlab/gerar_volta_sintetica.m` grava o `.mif` em **matlab/** e
**stim/**, e grava `.hex` / `.txt` em **stim/**. Não é necessário copiar à mão
depois de regenerar.

CSV (`volta_sintetica.csv`) permanece só em `matlab/` — é inspeção humana, não
formato de ROM.

---

## Quartus / `lap_rom` nesta v1

A síntese **não** lê o `.mif` ainda. `lap_rom.vhd` usa o array constante em
`rtl/lap_rom_init.vhd` (mesmos 900 números), de propósito: sim e placa batem
sem MegaWizard / `altsyncram`.

O `.qsf` (`quartus/ers_ep4ce6.qsf`) lista só VHDL — **não há** `INIT_FILE`.
Por isso o path Quartus **não foi trocado** nesta v1 (não havia string de
`.mif` para inverter).

Quando a ROM passar a IP com `INIT_FILE`, apontar para:

```
../stim/volta_sintetica.mif
```

(ou `../stim/volta_sintetica.hex` Intel HEX). Não apontar para `matlab/`.

Após regenerar o perfil, alinhar também `rtl/lap_rom_init.vhd` se a ROM VHDL
constante continuar em uso.
