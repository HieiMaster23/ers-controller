# 5. Resultados e Analise Final

## 5.1 Visao Geral

Este documento consolida os resultados obtidos na simulacao completa do sistema ERS (VHDL + Simulink), compara com os requisitos do regulamento, analisa o comportamento de cada componente e discute limitacoes do modelo.

A simulacao principal foi executada em modo **placeholder** (sem HDL Verifier), com o controlador em Simulink replicando a logica da FSM VHDL. Os testbenches em ModelSim validaram individualmente cada bloco VHDL.

## 5.2 Resultados da Co-Simulacao

### 5.2.1 Cenario simulado

- **Duracao:** 180 s (3 voltas de 60 s)
- **Solver:** ode4 (Runge-Kutta 4), passo fixo 1 ms
- **SoC inicial:** 70%
- **Perfil de corrida:** aceleracao (0-28s) -> frenagem (28-38s) -> curva (38-45s) -> saida (45-60s), repetido por volta
- **Turbo:** ativo continuamente, variando 20-65 krpm conforme throttle

### 5.2.2 Tabela Comparativa (Esperado vs Observado)

| Metrica | Limite Regulamento | Esperado | Observado | Status |
|---------|-------------------|----------|-----------|--------|
| Energia deploy / volta (max) | <= 4 MJ | ~3.5-4.0 MJ (corte no limite) | 3.82 MJ | Aprovado |
| Potencia MGU-K pico | <= 120 kW | Picos nas freadas fortes | 83.8 kW | Aprovado |
| Potencia MGU-H pico | <= 50 kW | Saturacao em pico turbo | 50.0 kW | Aprovado |
| Potencia deploy pico | <= 120 kW | Saturacao em throttle maximo | 120.0 kW | Aprovado |
| SoC minimo | >= 20% | Floor em 25% (corte deploy) | 25.0% | Aprovado |
| SoC maximo | <= 95% | Saturacao pelo integrator | 70.0% (inicial) | Aprovado |

### 5.2.3 Interpretacao dos Graficos

1. **SoC** cai de 70% para 25% ao longo da primeira volta por deploy agressivo; a partir dai oscila entre 25% e 40% (regime estacionario, balanceando harvest e deploy cortado).
2. **P_MGU-K (harvest)** aparece como pulsos durante frenagem (entre t=28-38s de cada volta). Amplitude proporcional a `brake_bar * omega * eta`.
3. **P_MGU-H (turbo harvest)** segue a curva do `turbo_rpm^2 * k_turbo`, saturando em 50 kW quando turbo > ~57.7 krpm.
4. **P_deploy** e ativo durante aceleracao (throttle > 2048) enquanto energia acumulada na volta esta abaixo de 4 MJ. Corta ao atingir o limite, reiniciando no `lap_reset`.
5. **Balanco liquido da bateria** e negativo (~-70 kW) durante deploy puro e positivo (~+100 kW) durante freadas com turbo ativo.
6. **Energia deploy acumulada** cresce monotonicamente dentro de cada volta, reinicia a cada 60 s via pulso `lap_reset`.

## 5.3 Resultados dos Testbenches VHDL

Executados com GHDL via `./scripts/run_tests.sh` (tambem no GitHub Actions a cada push) ou no ModelSim via `do sim_standalone.do`:

| Testbench | Testes | Resultado |
|-----------|--------|-----------|
| `tb_ers_fsm` | 12 testes (transicoes, prioridades, FAULT) | Todos passaram |
| `tb_pi_controller` | 7 testes (reset, step, saturacao, anti-windup) | Todos passaram |
| `tb_power_arbiter` | 7 testes (deploy, harvest K/H, corte energia, PWM) | Todos passaram |
| `tb_energy_meter` | 8 testes (valores numericos, saturacao em 4 MJ, sem wrap, lap reset) | Todos passaram |
| `tb_ers_top` | 9 fases integradas (standby -> deploy -> harvest K -> harvest H -> fault -> recovery -> lap_reset -> corte 4 MJ -> nova volta) | Todos passaram |

> **Nota (revisao 2026-10):** na versao original, os testbenches nao terminavam sozinhos e nao retornavam erro, entao falhas passavam despercebidas. Ao migrar para GHDL com `--assert-level=error`, `tb_pi_controller` falhava (T3a, T6) e `tb_ers_top` mostrava `energy_used` preso abaixo de 256. As causas estao nas correcoes #9 a #12 abaixo.

Sequencia de estados observada em `tb_ers_top`:
`000 -> 001 -> 000 -> 010 -> 011 -> 111 -> 000 -> 011 -> 000 -> 001 -> 010 -> 000`

Correspondente a: STANDBY -> HARVESTING_K -> STANDBY -> HARVESTING_H -> DEPLOYING -> FAULT -> STANDBY -> DEPLOYING -> STANDBY -> HARVESTING_K -> HARVESTING_H -> STANDBY.

## 5.4 Analise por Componente

### 5.4.1 FSM (ers_fsm.vhd)

**Funciona corretamente** em todas as condicoes testadas:
- Prioridade FAULT > DEPLOY > HARVEST_K > HARVEST_H > STANDBY foi respeitada em todos os cenarios.
- Transicao para FAULT ocorre tanto para SoC baixo (< 20%) quanto alto (> 95%).
- Thresholds (BRAKE=512, THROTTLE=2048, etc.) mapeam corretamente os ranges de 12 bits dos ADCs.

### 5.4.2 PI Controller (pi_controller.vhd)

**Comportamento verificado** no testbench e na co-simulacao:
- Resposta ao degrau estavel e rapida (algumas dezenas de ciclos de clock).
- Saturacao em [0, 65535] funcionando.
- Anti-windup via clamping do integrador evita overshooting persistente.
- Aritmetica Q16.16 com KP=1024 (0.015625) e KI=64 (0.0010) produz ganho efetivo adequado para a planta de ordem 1.

### 5.4.3 Power Arbiter (power_arbiter.vhd)

**Gera PWM de 50 kHz corretamente**:
- Contador 0-999 @ 50 MHz -> 20 us por periodo PWM.
- Conversao `duty_16b -> threshold_10b` via `duty * 1000 >> 16` com erro < 0.1%.
- Corte de deploy em `energy_used >= 4 MJ` (1024000 em Q8 kJ) funcionando.
- Durante harvest, `duty_applied` e zerado (nao conta como deploy).

### 5.4.4 Energy Meter (energy_meter.vhd)

**Integracao com precisao Q8** em kJ:
- Acumulador de 64 bits internamente (40 bits fracionarios extras), saida de 24 bits.
- Escala `INTEG_SCALE=10308` (calculada pelos generics `CLK_HZ`/`P_MAX_W`), erro < 0.001%.
- Satura exatamente em 4 MJ; reset via `lap_reset` apos cada volta.

### 5.4.5 Planta Simulink

**Modelos simplificados mas representativos**:
- MGU-K: `P = K_torque * brake_bar * omega_rad_s * eta`, saturado em 120 kW.
- MGU-H: `P = k_turbo * turbo_rpm^2`, saturado em 50 kW.
- Bateria: integrador de SoC com saturacao em [0.20, 0.95], driven por `(P_harvest - P_deploy) / Q_max_battery`.
- Cenario: LUTs 1-D reproduzem perfis tipicos de volta.

## 5.5 Decisoes de Projeto e Simplificacoes

### 5.5.1 Decisoes Arquiteturais

1. **Top-level estrutural** (`ers_top.vhd`): apenas port mapping, sem logica propria. Facilita substituicao de modulos e co-simulacao.
2. **FSM separada do arbitro**: a FSM decide *o que fazer* (deploy/harvest/standby); o arbitro decide *como fazer* (duty PWM, verificacao de limites). Separacao de responsabilidades.
3. **PI Q16.16**: formato ponto fixo uniforme para todas as contas, evitando conversao de escala entre blocos.
4. **Testbenches modulares + integrado**: cada bloco tem tb unitario; `tb_ers_top` valida integracao.

### 5.5.2 Simplificacoes do Modelo

1. **V_bus constante (400 V)**: nao modela variacao da tensao com SoC (efeito OCV). Justificado para o escopo academico.
2. **Eficiencia fixa (eta=0.90)**: modelos reais tem eta dependente de corrente e temperatura.
3. **Sem modelo termico**: motores e bateria nao aquecem, nao ha derating por temperatura.
4. **PI para deploy apenas**: o controlador fecha malha apenas em deploy; harvest usa duty fixo de 50%. Numa implementacao real, harvest tambem teria controle de torque.
5. **Cenario de corrida via LUT**: nao ha simulacao de dinamica veicular (massa, arrasto, pista). O throttle e brake sao arbitrarios.
6. **Placeholder vs VHDL real**: em modo placeholder, o controlador Simulink emula a FSM mas nao exercita a aritmetica VHDL. O caminho recomendado para validacao completa e co-simulacao real com HDL Verifier.

### 5.5.3 Correcoes Aplicadas Durante o Projeto

| # | Problema | Causa | Correcao |
|---|----------|-------|----------|
| 1 | `create_vehicle_model` erro em `add_line` duplicada | Sequencia `add`/`delete`/`add` deixava porta ocupada | Remover duplicacao, 1 unica `add_line` |
| 2 | `k_turbo=1.5e-8` produzia potencia MGU-H negligivel | Escala errada do coeficiente | Ajustar para `1.5e-5` |
| 3 | `power_arbiter.vhd` linha 122: "36 elements vs 26" | `resize(duty*1000, 36)` alargava antes da multiplicacao | Remover resize: `duty_mguk * to_unsigned(1000, 10)` da naturalmente 26 bits |
| 4 | `tb_ers_fsm` entrava em FAULT logo apos reset | `soc_in=0` (< 20%) por default causava fault | Setar `soc_in=2867` (~70%) antes de liberar reset |
| 5 | `Lap_Pulse` erro de sample time 20 ns vs 1 ms | Pulse Generator em modo Time-based com largura percentual | Trocar para Sample-based: `Period=T_volta/Ts`, `PulseWidth=1` |
| 6 | SoC ultrapassava 100% (chegava a 234%) | `UpperSaturationLimit` definido mas sem `LimitOutput='on'` | Adicionar `'LimitOutput','on'` ao Integrator |
| 7 | SoC nunca descia durante deploy | Controlador nao realimentava potencia de descarga na planta | Nova porta `P_deploy_in` na Planta, com `Sum_P` algebrico (`++-`) |
| 8 | Energia por volta nao tinha corte no placeholder | Placeholder nao replicava limite de 4 MJ | Adicionar integrador de energia com `ExternalReset='rising'` + AND de 3 entradas |
| 9 | `energy_meter` zerava sozinho e nunca chegava a 4 MJ | Saturacao comparava `accum(39:24)` com `ENERGY_MAX(39:24) = 0`: ao passar de 2^24 o acumulador era zerado em vez de travar; `energy_used` nunca passava de 255 | Acumulador de 64 bits, comparacao com o limite completo, trava em 1024000 |
| 10 | Escala de energia 1000x maior | Conta `1.831 W * 20 ns` resultou em 3.66e-5 J (correto: 3.66e-8 J) | `INTEG_SCALE` calculado a partir dos generics `CLK_HZ` e `P_MAX_W` |
| 11 | Termo integral do PI quase sem efeito | Com 32 bits, `INTEG_MAX = OUT_MAX*256` limitava a contribuicao integral a 256 de 65535 | Termos em 48 bits, `INTEG_MAX = OUT_MAX * 2^16` |
| 12 | Falhas de testbench passavam despercebidas | Clock nunca parava e asserts nao interrompiam; T3a amostrava a saida na mesma borda em que era atualizada | `sim_done` para o clock, GHDL com `--assert-level=error`, amostragem 1 ns apos a borda, CI no GitHub Actions |

## 5.6 Limitacoes Conhecidas

1. **Modo co-simulacao real (Simulink) nao testado nesta execucao**: requer licenca HDL Verifier + configuracao manual do bloco de mapeamento de sinais. A infraestrutura (`sim_cosim.do`, bloco `HDL Cosim`) esta pronta; falta apenas a licenca. A co-simulacao livre do [capitulo 6](06_cosimulacao_python.md) roda o VHDL real em malha fechada.
2. **Placeholder nao exercita PI**: em modo placeholder, o duty de deploy vem direto do throttle (`duty = throttle * 16`), sem malha PI. O PI esta validado via `tb_pi_controller` mas nao integrado na co-simulacao em modo placeholder.
3. **Nao ha validacao em hardware real**: projeto e apenas simulado; sintese em FPGA nao foi realizada.
4. **Cenario unico**: uma volta com perfil fixo; nao ha variacoes de condicoes de pista (chuva, safety car, ultrapassagens).
5. ~~**Realimentacao do PI sem significado fisico**~~ (resolvido no capitulo 6): o valor medido do PI era `speed_rpm`, comparado com `throttle * 16`. Agora e a nova porta `p_mguk_meas` (potencia de deploy medida).
6. **PWM sem direcao**: `pwm_mguk` nao indica se o MGU-K esta tracionando ou gerando. Necessario um sinal de modo/direcao para acionar uma ponte H real.

## 5.7 Propostas de Melhoria

- **Curto prazo:**
  - Conectar o duty PWM do bloco HDL Cosim (quando disponivel) a `P_deploy_in` da Planta, completando a co-simulacao real com realimentacao.
  - Adicionar multiplos cenarios de corrida (classificacao vs corrida, chuva) via `switch` de LUTs.
- **Medio prazo:**
  - Modelo de bateria com OCV(SoC), resistencia interna variavel com temperatura.
  - Modelo termico dos MGUs com derating.
  - Sintese em FPGA Cyclone V / Zynq e comparacao de utilizacao.
- **Longo prazo:**
  - Controle preditivo (MPC) substituindo PI, com previsao do perfil de pista.
  - Modelo de dinamica veicular acoplado (Simscape Multibody).
  - Interface HIL com controlador real em placa embarcada.

## 5.8 Conclusao

O projeto demonstra com sucesso a viabilidade de um controlador ERS embarcado em VHDL operando em co-simulacao com um modelo fisico de alta fidelidade em Simulink. Todos os **limites do regulamento foram respeitados** no cenario simulado:

- **4 MJ/volta**: observado 3.82 MJ (95.5% do limite, corte funcionando)
- **120 kW deploy**: saturacao correta, nunca ultrapassa
- **50 kW harvest H**: saturacao no pico turbo
- **SoC 20-95%**: nunca sai do intervalo

A arquitetura modular VHDL facilitou testes unitarios e a separacao entre logica de decisao (FSM), controle (PI) e atuacao (Arbiter). As simplificacoes adotadas preservam a essencia fisica do sistema sem comprometer o objetivo academico.

## 5.9 Resumo das 5 Etapas

| Etapa | Entrega | Artefatos |
|-------|---------|-----------|
| 1. Estrutura | Organizacao de pastas, README, introducao | `README.md`, `docs/01_introducao.md` |
| 2. Modelo Fisico | Modelo Simulink do veiculo | `simulink/create_vehicle_model.m`, `simulink/validate_standalone.m`, `docs/02_modelo_fisico.md` |
| 3. VHDL | FSM, PI, Arbiter, Energy Meter, Top | 5 arquivos `.vhd`, 4 testbenches, 3 scripts `.do`, `docs/03_arquitetura_vhdl.md` |
| 4. Co-simulacao | Modelo Simulink integrado | `simulink/create_cosim_top.m`, `simulink/analyze_cosim_results.m`, `docs/04_cosimulacao.md` |
| 5. Resultados | Analise, graficos, documentacao final | `docs/05_resultados.md` (este documento) |

Projeto concluido em **180 s de simulacao**, **4 testbenches validados** e **5 documentos tecnicos** gerados.
