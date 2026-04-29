# 1. Introducao

## 1.1 Motivacao Academica

O desenvolvimento de sistemas embarcados de alta performance e com restricoes temporais rigorosas e uma das areas mais desafiadoras da engenharia eletronica e de computacao. Este projeto propoe a simulacao de um **Energy Recovery System (ERS)** -- sistema presente nos carros de Formula 1 modernos -- como caso de estudo para aplicar conceitos de:

- **Projeto digital em VHDL** com maquinas de estados finitos (FSM)
- **Aritmetica de ponto fixo** em hardware (formato Q16.16)
- **Co-simulacao** entre modelo fisico (Simulink) e controlador digital (ModelSim)
- **Verificacao funcional** com testbenches estruturados

A escolha do ERS como tema se justifica pela riqueza de problemas que ele encapsula: controle em tempo real, gerenciamento de energia com restricoes regulamentares, interacao entre subsistemas eletricos e mecanicos, e a necessidade de decisoes autonomas em alta frequencia.

## 1.2 O que e o ERS e por que e relevante

O Energy Recovery System e um conjunto de componentes eletricos que permite a um carro de corrida **recuperar energia** que seria desperdicada (calor dos freios, gases de escapamento) e **reutiliza-la** para aumentar a potencia disponivel nas rodas.

Nos carros de Formula 1 atuais, o ERS e composto por:

- **MGU-K (Motor Generator Unit - Kinetic):** Acoplado ao eixo de transmissao. Durante frenagens, funciona como gerador, convertendo energia cinetica em eletrica. Na aceleracao, funciona como motor, adicionando ate 120 kW de potencia eletrica.

- **MGU-H (Motor Generator Unit - Heat):** Acoplado ao turbocompressor. Recupera energia dos gases de escapamento e tambem pode ser usado para controlar a velocidade do turbo (eliminando turbo lag).

- **Bateria de Alta Tensao (Energy Store):** Armazena a energia recuperada pelos MGUs. Opera tipicamente em torno de 400V com restricoes rigidas de estado de carga (SoC).

- **Controlador Eletronico (CE):** O "cerebro" do sistema. Decide em tempo real quando recuperar energia, quando injeta-la, e garante que os limites do regulamento sejam respeitados.

Este projeto implementa o **Controlador Eletronico** em VHDL (como seria feito em uma FPGA real) e o restante do sistema em Simulink (modelo fisico da planta).

## 1.3 Objetivos do Projeto

1. **Implementar um controlador ERS em VHDL** que opera como maquina de estados finitos, decidindo autonomamente o modo de operacao (harvest, deploy, standby, fault).

2. **Desenvolver um modelo fisico simplificado** do trem de forca eletrico em Simulink, incluindo MGU-K, MGU-H e modelo de bateria RC de primeira ordem.

3. **Realizar co-simulacao** entre o controlador VHDL (ModelSim) e a planta fisica (Simulink) usando HDL Verifier, validando o comportamento do sistema integrado.

4. **Verificar o cumprimento dos requisitos regulamentares:** energia maxima por volta de 4 MJ, potencia limitada a 120 kW, e estado de carga da bateria entre 20% e 95%.

5. **Documentar todas as decisoes de projeto**, simplificacoes adotadas e resultados obtidos.

## 1.4 Ferramentas Utilizadas

| Ferramenta | Justificativa |
|---|---|
| **VHDL (VHDL-93)** | Linguagem padrao para descricao de hardware sintetizavel. Escolhida por ser o foco da disciplina e por permitir implementacao real em FPGA. |
| **ModelSim / Questa** | Simulador VHDL de referencia na industria. Permite simulacao ciclo a ciclo e integracao com HDL Verifier. |
| **MATLAB / Simulink** | Ambiente padrao para modelagem de sistemas fisicos e controle. Permite prototipagem rapida do modelo da planta. |
| **Simscape Electrical** | Biblioteca do Simulink especializada em modelagem de circuitos eletricos. Simplifica a criacao dos modelos de MGU e bateria. |
| **HDL Verifier** | Toolbox do MATLAB que permite co-simulacao direta entre Simulink e ModelSim via TCP, sem necessidade de conversores manuais. |

## 1.5 Arquitetura Geral do Sistema

```
+================================================================+
|                    SIMULINK (Planta Fisica)                     |
|                                                                |
|  +-------------+  +-------------+  +-----------+  +---------+ |
|  | Cenario de  |  |   MGU-K     |  |  MGU-H    |  | Bateria | |
|  | Corrida     |->| (Frenagem/  |->| (Turbo/   |->| HV      | |
|  | (speed,     |  |  Tracao)    |  |  Escape)  |  | (SoC,V) | |
|  |  brake,     |  +------+------+  +-----+-----+  +----+----+ |
|  |  throttle)  |         |               |              |      |
|  +-------------+         v               v              v      |
|                    speed_rpm        turbo_rpm        soc_in     |
|                    brake_pres                                   |
|                    throttle                                     |
+====================||============================||============+
                     ||  HDL Cosimulation (TCP)    ||
                     \/                            /\
+====================||============================||============+
|                   MODELSIM (Controlador VHDL)                  |
|                                                                |
|  +------------------------------------------------------------+|
|  |                     ers_top.vhd                            ||
|  |                                                            ||
|  |  +----------------+    +------------------+                ||
|  |  |  ers_fsm.vhd   |--->| pi_controller.vhd|               ||
|  |  | (Maquina de    |    | (Controle PI     |                ||
|  |  |  Estados)      |    |  ponto fixo Q16) |                ||
|  |  +-------+--------+    +--------+---------+                ||
|  |          |                       |                          ||
|  |          v                       v                          ||
|  |  +----------------+    +------------------+                ||
|  |  |power_arbiter   |<---| energy_meter.vhd |               ||
|  |  | (Limites do    |    | (Integrador de   |                ||
|  |  |  regulamento)  |    |  energia/volta)  |                ||
|  |  +-------+--------+    +------------------+                ||
|  |          |                                                  ||
|  |          v                                                  ||
|  |    pwm_mguk, pwm_mguh, ers_mode, fault_flag                ||
|  +------------------------------------------------------------+|
+================================================================+
```

### Fluxo de operacao:

1. O **Cenario de Corrida** (Simulink) gera os sinais de velocidade, pressao de freio, posicao do acelerador e RPM do turbo, simulando uma volta completa.

2. Esses sinais sao convertidos para representacao digital e enviados ao **controlador VHDL** via co-simulacao TCP.

3. A **FSM** (`ers_fsm.vhd`) analisa os sinais de entrada e decide o modo de operacao: `STANDBY`, `HARVESTING_K`, `HARVESTING_H`, `DEPLOYING` ou `FAULT`.

4. O **controlador PI** (`pi_controller.vhd`) regula a corrente do MGU-K com base no modo selecionado, usando aritmetica de ponto fixo Q16.

5. O **arbitro de potencia** (`power_arbiter.vhd`) verifica se a potencia e energia estao dentro dos limites do regulamento antes de liberar os sinais PWM.

6. O **integrador de energia** (`energy_meter.vhd`) acumula a energia deployada a cada volta e sinaliza quando o limite de 4 MJ e atingido.

7. Os sinais de saida (PWM, modo, flags) retornam ao Simulink para atuar na planta fisica, fechando a malha de controle.
