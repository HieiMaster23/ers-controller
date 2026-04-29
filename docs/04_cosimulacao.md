# 4. Co-Simulacao ModelSim + Simulink

## 4.1 Visao Geral

A co-simulacao conecta o controlador VHDL (rodando no ModelSim) com a planta fisica (rodando no Simulink) em tempo de simulacao. A comunicacao e feita via TCP usando o HDL Verifier toolbox.

```
+----------------------------+     TCP:4449     +---------------------------+
|       SIMULINK             | <=============>  |       MODELSIM            |
|                            |                  |                           |
|  [Plant] --> speed_rpm  -->|-->  speed_rpm --> |  [ers_top.vhd]            |
|          --> brake_pres -->|-->  brake_pres -->|    |-- ers_fsm            |
|          --> throttle   -->|-->  throttle   -->|    |-- pi_controller      |
|          --> soc_adc    -->|-->  soc_in     -->|    |-- power_arbiter      |
|          --> turbo_rpm  -->|-->  turbo_rpm  -->|    |-- energy_meter        |
|          --> lap_reset  -->|-->  lap_reset  -->|                           |
|                            |                  |                           |
|  [Scopes] <-- pwm_mguk <--|<-- pwm_mguk   <--|                           |
|           <-- ers_mode  <--|<-- ers_mode   <--|                           |
|           <-- energy    <--|<-- energy_used<--|                           |
|           <-- fault     <--|<-- fault_flag <--|                           |
+----------------------------+                  +---------------------------+
```

## 4.2 Arquivos da Etapa 4

| Arquivo | Funcao |
|---------|--------|
| `simulink/create_cosim_top.m` | Gera o modelo `cosim_top.slx` |
| `simulink/analyze_cosim_results.m` | Analisa dados e verifica regulamento |
| `scripts/sim_cosim.do` | Inicializa ModelSim para co-simulacao |

## 4.3 Pre-requisitos

- MATLAB R2022b ou superior
- HDL Verifier toolbox (licenca ativa)
- ModelSim/Questa instalado e acessivel pelo PATH
- Projeto VHDL compilado (via `compile_all.do`)

## 4.4 Passo a Passo: Co-Simulacao Real (com HDL Verifier)

### Passo 1: Compilar VHDL no ModelSim

```tcl
cd "C:/Users/Rafael/Documents/Projetos/Simulador ERS/ers_project/scripts"
do compile_all.do
```

### Passo 2: Iniciar sessao de co-simulacao no ModelSim

```tcl
do sim_cosim.do
```

Isso carrega `ers_top` e abre a porta TCP 4449. O ModelSim fica aguardando o Simulink.

### Passo 3: Gerar modelo no MATLAB

```matlab
cd('C:/Users/Rafael/Documents/Projetos/Simulador ERS/ers_project/simulink');
create_cosim_top
```

Se HDL Verifier estiver instalado, o script cria o bloco `HDL Cosimulation`. Caso contrario, cria um controlador placeholder em Simulink.

### Passo 4: Configurar bloco HDL Cosimulation

Abra `cosim_top.slx` e dê duplo clique no bloco `HDL_Cosim`:

1. **Aba "Ports":** Adicionar os sinais de entrada e saida:

    | Nome do sinal | Direcao | Tipo | Largura |
    |---------------|---------|------|---------|
    | `clk` | Input (force clock) | Clock | 1 |
    | `rst_n` | Input (force) | Reset | 1 |
    | `speed_rpm` | Input | Unsigned | 16 |
    | `brake_pres` | Input | Unsigned | 12 |
    | `throttle` | Input | Unsigned | 12 |
    | `soc_in` | Input | Unsigned | 12 |
    | `turbo_rpm` | Input | Unsigned | 16 |
    | `lap_reset` | Input | Logic | 1 |
    | `pwm_mguk` | Output | Logic | 1 |
    | `pwm_mguh` | Output | Logic | 1 |
    | `ers_mode` | Output | Unsigned | 3 |
    | `energy_used` | Output | Unsigned | 24 |
    | `fault_flag` | Output | Logic | 1 |

2. **Aba "Clock":** Configurar:
    - Rising edge clock: `clk`
    - Clock period: `20 ns` (50 MHz)

3. **Aba "Connection":**
    - Connection method: `SharedMemory` (mesmo PC) ou `Socket` (porta 4449)

4. **Aba "Timescales":**
    - Simulink sample time: `Ts` (1e-3 s)
    - HDL time: `20 ns`
    - Isso significa que cada step do Simulink (1 ms) corresponde a 50000 ciclos de clock VHDL

### Passo 5: Conectar sinais

Conectar as saidas do bloco `Plant` as entradas do bloco `HDL_Cosim`, e as saidas do `HDL_Cosim` aos Scopes:

- `Plant/speed_rpm` --> `HDL_Cosim/speed_rpm`
- `Plant/brake_pres` --> `HDL_Cosim/brake_pres`
- `Plant/throttle` --> `HDL_Cosim/throttle`
- `Plant/soc_adc` --> `HDL_Cosim/soc_in`
- `Plant/turbo_rpm` --> `HDL_Cosim/turbo_rpm`
- `Plant/lap_reset` --> `HDL_Cosim/lap_reset`
- `HDL_Cosim/pwm_mguk` --> `Scope` (novo)
- `HDL_Cosim/ers_mode` --> `Scope` (novo)
- `HDL_Cosim/energy_used` --> `Scope` (novo)

### Passo 6: Executar

1. Verificar que o ModelSim esta com `ers_top` carregado e aguardando
2. No Simulink, clicar "Run" (ou `sim('cosim_top')`)
3. Simulacao de 180s (3 voltas) inicia
4. Observar os Scopes em tempo real

### Passo 7: Analisar resultados

```matlab
analyze_cosim_results
```

## 4.5 Modo Placeholder (sem HDL Verifier)

Se o HDL Verifier nao estiver disponivel, o script `create_cosim_top.m` detecta automaticamente e cria um **controlador placeholder** em Simulink que emula o comportamento basico da FSM:

- Deploy quando `throttle > 2048` e `SoC > 25%`
- Duty proporcional ao throttle
- Sem harvest, sem integracao de energia completa

Este modo permite testar a infraestrutura do modelo e os Scopes, mas **nao substitui a co-simulacao real** para validacao do VHDL.

Para testar:
```matlab
create_cosim_top    % detecta automaticamente se tem HDL Verifier
sim('cosim_top')    % roda simulacao
analyze_cosim_results  % analisa dados
```

## 4.6 Mapeamento de Sinais VHDL <-> Simulink

| Porta Simulink (Plant saida) | Sinal VHDL (ers_top entrada) | Tipo | Escala |
|------------------------------|------------------------------|------|--------|
| `speed_rpm` | `speed_rpm` | uint16 | 1 RPM = 1 LSB |
| `brake_pres` | `brake_pres` | uint12 | 0-100 bar -> 0-4095 |
| `throttle` | `throttle` | uint12 | 0-100% -> 0-4095 |
| `soc_adc` | `soc_in` | uint12 | 0-100% -> 0-4095 |
| `turbo_rpm` | `turbo_rpm` | uint16 | 1 RPM = 1 LSB |
| `lap_reset` | `lap_reset` | logic | Pulso de 1 amostra por volta |

| Sinal VHDL (ers_top saida) | Uso no Simulink | Tipo | Descricao |
|----------------------------|-----------------|------|-----------|
| `pwm_mguk` | Scope + controle MGU-K | logic | PWM 50 kHz |
| `pwm_mguh` | Scope + controle MGU-H | logic | PWM 50 kHz |
| `ers_mode` | Scope monitoramento | uint3 | Estado da FSM |
| `energy_used` | Scope monitoramento | uint24 | Energia kJ (Q8) |
| `fault_flag` | Scope + alarme | logic | Falha ativa |

## 4.7 Problemas Conhecidos e Solucoes

### 1. "Connection refused" ao iniciar simulacao
**Causa:** ModelSim nao esta rodando ou `ers_top` nao esta carregado.
**Solucao:** Executar `do sim_cosim.do` no ModelSim antes de iniciar no Simulink.

### 2. "Signal not found" ao configurar bloco HDL Cosim
**Causa:** Os nomes dos sinais no bloco nao correspondem aos do VHDL.
**Solucao:** Verificar que os nomes sao exatamente como declarados em `ers_top.vhd` (case-insensitive, mas sem espacos).

### 3. Simulacao muito lenta
**Causa:** O Simulink precisa sincronizar com o ModelSim a cada passo, e cada passo de 1 ms gera 50000 ciclos VHDL.
**Solucao:** Aumentar `Ts` para 5e-3 (5 ms) se performance for prioridade. A dinamica do modelo e lenta o suficiente.

### 4. Valores incorretos nas entradas do VHDL
**Causa:** Sinais double do Simulink nao convertidos para inteiro.
**Solucao:** Adicionar blocos `Data Type Conversion` (uint16, uint12) entre a planta e o bloco HDL Cosim.

### 5. SoC nao varia durante co-simulacao (corrigido)
**Causa original:** O PWM do controlador VHDL nao estava sendo realimentado na planta, entao a bateria so acumulava harvest, sem descarga.
**Solucao aplicada:** A partir desta versao, o controlador (placeholder ou HDL) expoe uma saida `P_deploy` (potencia em W) que e realimentada a uma nova entrada `P_deploy_in` da planta. A bateria calcula `P_liquido = P_mguk + P_mguh - P_deploy` e integra. Alem disso, o integrador do SoC agora tem `LimitOutput='on'` com saturacao em `[0.20, 0.95]`, garantindo que o SoC nunca saia do intervalo do regulamento.

Em modo HDL real, `P_deploy_in` recebe `Constant(0)` por padrao — o usuario deve conectar manualmente um bloco de conversao `pwm_duty -> P_deploy` alimentado pela saida PWM do bloco HDL Cosim para habilitar a descarga.

### 6. Limite de 4 MJ/volta no controlador placeholder
O controlador em Simulink (modo sem HDL Verifier) agora inclui um integrador de energia por volta com reset externo via `lap_reset`. Quando a energia acumulada excede 4 MJ, o AND de 3 entradas corta o deploy ate o proximo reset de volta. Isso replica o comportamento do `energy_meter` + `ers_fsm` em VHDL.

## 4.8 Escala Temporal

| Dominio | Passo | Frequencia |
|---------|-------|------------|
| Simulink (planta) | 1 ms | 1 kHz |
| VHDL (controlador) | 20 ns | 50 MHz |
| PWM gerado | 20 us | 50 kHz |

A cada passo do Simulink (1 ms), o VHDL executa **50000 ciclos de clock**. O bloco HDL Cosimulation gerencia essa diferenca de escala automaticamente.
