# ERS Simulation Project

Simulador de Sistema de Recuperação de Energia (ERS) inspirado em regulamentos de Formula 1. Há **duas árvores independentes** neste repositório:

1. **Controlador VHDL + co-simulação Simulink/ModelSim** (`simulink/`, `vhdl/`, `testbench/`, `docs/`, `scripts/`) — trabalho anterior.
2. **Protótipo FPGA Cyclone IV EP4CE6** (`fpga-ep4ce6/`) — VHDL-93 com dashboard VGA, ROM de volta sintética e projeto Quartus II 13.0sp1.

## Objetivo

Projeto acadêmico que demonstra o funcionamento de um controlador eletrônico embarcado de alta exigencia temporal, aplicado ao gerenciamento de energia em um carro de corrida. O sistema decide quando recuperar energia (frenagem e turbo) e quando injeta-la na tração, respeitando limites rígidos do regulamento.

## Arquitetura do Sistema

```
+---------------------------+          +----------------------------+
|   Simulink (Planta)       |   TCP    |   ModelSim (Controlador)   |
|                           | <------> |                            |
|  - MGU-K (freio)          |  HDL     |  ers_top.vhd               |
|  - MGU-H (turbo)          | Cosim    |   +-- ers_fsm.vhd          |
|  - Bateria HV (RC 1a ord) |          |   +-- pi_controller.vhd    |
|  - Cenario de corrida     |          |   +-- power_arbiter.vhd    |
+---------------------------+          |   +-- energy_meter.vhd      |
                                       +----------------------------+
```

## Restrições do Regulamento Simulado

Valores da **árvore Simulink/controlador** (`docs/`, `simulink/`, `vhdl/`). São limites do modelo acadêmico — **não são números oficiais da FIA**. O protótipo FPGA em `fpga-ep4ce6/` usa unidades inteiras próprias (`ers_pkg.vhd`); não misture as duas escalas.

| Parametro                       | Limite     |
|---------------------------------|------------|
| Energia máxima por volta        | 4 MJ       |
| Potência máxima deploy (MGU-K)  | 120 kW     |
| Potência máxima harvest (MGU-K) | 120 kW     |
| SoC mínimo da bateria           | 20%        |
| SoC maximo da bateria           | 95%        |
| Tensão nominal barramento HV    | 400 V      |

## Ferramentas

| Ferramenta           | Funcao                                          |
|----------------------|-------------------------------------------------|
| ModelSim / Questa    | Simulação e verificação do VHDL                  |
| MATLAB / Simulink    | Modelo físico do veículo e co-simulacao          |
| Simscape Electrical  | Modelagem dos componentes elétricos              |
| HDL Verifier         | Bloco de co-simulação entre Simulink e ModelSim  |
| Quartus II 13.0sp1   | Síntese do protótipo FPGA EP4CE6 (`fpga-ep4ce6/`) |

## Alvo FPGA — EP4CE6 (dashboard VGA)

O diretório [`fpga-ep4ce6/`](fpga-ep4ce6/) é o **alvo de placa** para iterar no Cursor: protótipo VHDL-93 para **Altera Cyclone IV E EP4CE6E22C8**, Quartus II **13.0sp1**, dashboard VGA gerado por pixel (sem framebuffer) e ROM de **volta sintética de exemplo** (90 s, 900 amostras — **não é um circuito real**).

- Abra o projeto em **`fpga-ep4ce6/quartus/ers.qpf`** no Quartus II 13.0sp1 (revisão `ers_ep4ce6`, top `ers_top`).
- Pinos de I/O estão como **placeholders** (`PIN_XX`) — ver [`fpga-ep4ce6/quartus/PINOS.md`](fpga-ep4ce6/quartus/PINOS.md). Preencha pelo esquemático da placa; **não invente números de pino**.
- Constantes de energia/potência são **unidades escaladas de protótipo**, inspiradas em F1 — **não são números oficiais da FIA**.
- v1: apenas MGU-K + energy store (sem MGU-H). README detalhado em [`fpga-ep4ce6/README.md`](fpga-ep4ce6/README.md).

Esta árvore **não substitui** o controlador Simulink em `vhdl/` / `simulink/`; as duas convivem no mesmo repositório.

## Estrutura do Projeto

```
ers_project/
+-- README.md
+-- docs/
|   +-- 01_introducao.md
|   +-- 02_modelo_fisico.md
|   +-- 03_arquitetura_vhdl.md
|   +-- 04_cosimulacao.md
|   +-- 05_resultados.md
+-- simulink/
|   +-- vehicle_model.slx
|   +-- cosim_top.slx
+-- vhdl/                  (controlador co-simulação — árvore antiga)
|   +-- ers_fsm.vhd
|   +-- pi_controller.vhd
|   +-- power_arbiter.vhd
|   +-- energy_meter.vhd
|   +-- ers_top.vhd
+-- testbench/
|   +-- tb_ers_fsm.vhd
|   +-- tb_pi_controller.vhd
|   +-- tb_power_arbiter.vhd
|   +-- tb_ers_top.vhd
+-- scripts/
|   +-- compile_all.do
|   +-- sim_standalone.do
|   +-- sim_cosim.do
+-- fpga-ep4ce6/           (protótipo FPGA VGA — alvo de placa)
    +-- README.md
    +-- rtl/               VHDL-93 (ers_pkg, lap_rom, mgu_k, dash_vga, ers_top, …)
    +-- matlab/            gerador + volta_sintetica.mif / .csv (exemplo)
    +-- sim/               tb_ers.vhd, tb_ers_plant.vhd
    +-- quartus/           ers.qpf, ers_ep4ce6.qsf, ers.sdc, PINOS.md
```

## Documentação

- [Introdução e Motivação](docs/01_introducao.md)
- [Modelo Físico (Simulink)](docs/02_modelo_fisico.md)
- [Arquitetura VHDL](docs/03_arquitetura_vhdl.md)
- [Co-simulação](docs/04_cosimulacao.md)
- [Resultados e Análise](docs/05_resultados.md)
- [Protótipo FPGA EP4CE6 (VGA)](fpga-ep4ce6/README.md)

## Convenções de Código VHDL

- `snake_case` para sinais e portas; `UPPER_CASE` para constantes e generics
- Clock: `rising_edge(clk)`; reset assíncrono: `if rst_n = '0'`
- Biblioteca: `numeric_std` (nunca `std_logic_arith`)
- Ponto fixo: formato Q documentado em cada sinal
- Cabeçalho obrigatorio em cada arquivo

## Status

- [x] Etapa 1 -- Estrutura do projeto e documentação inicial
- [x] Etapa 2 -- Modelo físico no Simulink
- [x] Etapa 3 -- Implementacao VHDL (FSM, PI, Arbiter, Energy Meter, Top)
- [x] Etapa 4 -- Co-simulação (Simulink + placeholder / HDL Verifier)
- [x] Etapa 5 -- Análise de resultados e documentação final

**Co-simulação Simulink:** etapas 1–5 concluídas. Veja [docs/05_resultados.md](docs/05_resultados.md).

**FPGA EP4CE6:** protótipo VHDL-93 + Quartus 13.0sp1 em [`fpga-ep4ce6/`](fpga-ep4ce6/) (v1, sem MGU-H; pinos ainda placeholders).

## Resultados Principais

| Métrica | Limite | Observado | Status |
|---------|--------|-----------|--------|
| Energia deploy / volta | <= 4 MJ | 3.82 MJ | Aprovado |
| Potência MGU-K pico | <= 120 kW | 83.8 kW | Aprovado |
| Potência MGU-H pico | <= 50 kW | 50.0 kW | Aprovado |
| Potência deploy pico | <= 120 kW | 120.0 kW | Aprovado |
| SoC min / max | [20%, 95%] | [25%, 70%] | Aprovado |

**Testbenches VHDL:** 4/4 passando (ers_fsm, pi_controller, power_arbiter, ers_top) -- 33 testes individuais cobrindo transicoes, prioridades, saturacao, anti-windup, corte de energia e PWM.

## Como Reproduzir

```matlab
% 1. Modelo fisico standalone
create_vehicle_model
validate_standalone

% 2. Co-simulacao (placeholder)
create_cosim_top
out = sim('cosim_top');
analyze_cosim_results
```

```tcl
# Testbenches VHDL do controlador (ModelSim)
cd ers_project/scripts
do compile_all.do
do sim_standalone.do
```

```text
# Protótipo FPGA (Quartus II 13.0sp1)
# 1. Abra fpga-ep4ce6/quartus/ers.qpf
# 2. Preencha pinos em ers_ep4ce6.qsf (hoje PIN_XX — ver quartus/PINOS.md)
# 3. Processing → Start Compilation
# Simulação ModelSim: ver fpga-ep4ce6/README.md
```
