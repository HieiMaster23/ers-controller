# 3. Arquitetura VHDL

## 3.1 Visao Geral dos Modulos

```
                         ers_top.vhd
  +----------------------------------------------------------+
  |                                                          |
  |  speed_rpm ---+                                          |
  |  brake_pres --+--> [ers_fsm] --harvest_k_en--> [power_  |
  |  throttle ----+--> [       ] --harvest_h_en-->  arbiter] |---> pwm_mguk
  |  soc_in ------+--> [       ] --deploy_en-----> [       ] |---> pwm_mguh
  |  turbo_rpm ---+    [       ] --fault_active    [       ] |
  |                    [       ] <--energy_used--  [       ] |
  |                    +--------+                  [       ] |
  |                         |                      [       ] |
  |  throttle ----> setpoint|     +-----------+    [       ] |
  |                         v     |           |    [       ] |
  |                 [pi_controller]--duty_out->+-->[       ] |
  |  p_mguk_meas -> [            ]     duty_limited   |      |
  |                 +------------+         |          |      |
  |                                        v          |      |
  |                                [energy_meter]<----+      |
  |  lap_reset ------------------> [           ]             |
  |                                [           ]--energy_used|---> energy_used
  |                                +----------+              |
  +----------------------------------------------------------+
       |           |
       v           v
    ers_mode    fault_flag
```

## 3.2 Diagrama de Estados da FSM (`ers_fsm.vhd`)

```
                          rst_n = '0'
                              |
                              v
                    +-------------------+
                    |     STANDBY       |<-----------------------------+
                    |     (000)         |                              |
                    +-------------------+                              |
                     |    |    |    ^                                  |
        deploy_cond  | hk | hh |   | nenhuma                         |
                     |    |    |   | condicao                        |
                     v    v    v   |                                  |
     +-----------+  +-----------+  +-----------+                     |
     | DEPLOYING |  |HARVEST_K  |  |HARVEST_H  |                     |
     |   (011)   |  |  (001)    |  |  (010)    |                     |
     +-----------+  +-----------+  +-----------+                     |
          |              |              |                             |
          |  deploy=0    | brake=0      | turbo<40k                  |
          +----->--------+------>-------+---------->-----------------+
          |              |              |
          |   fault_cond |  fault_cond  | fault_cond
          +------+-------+------+-------+------+
                 |                              |
                 v                              |
         +-------------------+                  |
         |      FAULT        |                  |
         |      (111)        |--fault=0---------+
         +-------------------+

    Prioridade: FAULT > DEPLOYING > HARVEST_K > HARVEST_H > STANDBY
```

### Condicoes de transicao:

| Condicao | Expressao |
|----------|-----------|
| `fault_cond` | `soc < 819 (20%)` OR `soc > 3890 (95%)` |
| `deploy_cond` | `throttle > 2048` AND `soc > 1024 (25%)` AND `energy < 1024000` |
| `harvest_k_cond` | `brake_pres > 512` AND `soc < 3685 (90%)` |
| `harvest_h_cond` | `turbo_rpm > 40000` AND `soc < 3685 (90%)` |

### Saidas por estado:

| Estado | harvest_k_en | harvest_h_en | deploy_en | fault_active | ers_mode |
|--------|:---:|:---:|:---:|:---:|:---:|
| STANDBY | 0 | 0 | 0 | 0 | 000 |
| HARVESTING_K | 1 | 0 | 0 | 0 | 001 |
| HARVESTING_H | 0 | 1 | 0 | 0 | 010 |
| DEPLOYING | 0 | 0 | 1 | 0 | 011 |
| FAULT | 0 | 0 | 0 | 1 | 111 |

## 3.3 Controlador PI (`pi_controller.vhd`)

### Aritmetica Q16

O controlador PI opera em aritmetica de ponto fixo com 16 bits fracionarios. Os ganhos sao dados em Q16 (1.0 = 65536) e os termos P, I e a soma usam 48 bits signed (Q32.16).

48 bits sao necessarios porque o integrador precisa alcancar `OUT_MAX` na escala Q16: `65535 * 2^16 ~ 2^32`, que nao cabe em 32 bits signed. A versao original usava 32 bits e limitava o integrador a `OUT_MAX * 256` em Q16, ou seja, a apenas 256 unidades de duty (0.4% da faixa) -- o termo integral praticamente nao atuava.

```
Formato Q32.16 (signed 48 bits):
  Bit 47      = sinal
  Bits 46..16 = parte inteira
  Bits 15..0  = parte fracionaria (16 bits) -> resolucao 1/65536 = 1.53e-5

Exemplo: KP = 1024 em Q16 = 1024 / 65536 = 0.015625
         KI = 64 em Q16   = 64 / 65536   = 0.000977
```

### Algoritmo:

```
A cada ciclo de clock (se enable = '1'):
  1. error = setpoint - measured         (signed 17 bits)
  2. p_term = KP * error                 (signed 48 bits, Q16)
  3. i_accum += KI * error               (signed 48 bits, Q16, com clamping)
  4. pi_sum = p_term + i_accum           (signed 48 bits)
  5. output = pi_sum >> 16               (converter Q16 -> inteiro)
  6. duty_out = saturate(output, 0, 65535)
```

### Anti-windup:

O acumulador integral e limitado por clamping a faixa da saida, na escala Q16:
- `INTEG_MAX = OUT_MAX * 2^16` (contribuicao integral maxima = 65535)
- `INTEG_MIN = OUT_MIN * 2^16 = 0`

Se `i_accum + KI*error` exceder esses limites, o acumulador trava no limite. Isso evita que o integrador "carregue" excessivamente durante saturacao: quando o erro inverte de sinal, o termo P negativo tira a saida da saturacao ja no ciclo seguinte (verificado em `tb_pi_controller` T7).

### Resposta esperada:

Com KP=0.015625 e KI=0.000977, para um degrau de erro=5000:
- P imediato: 0.015625 * 5000 = 78.125
- I apos 10 ciclos: 0.000977 * 5000 * 10 = 48.8
- Total apos 10 ciclos: ~127 (saida deve ser > 50, criterio de aceitacao)

Para erro=60000 (saturacao): P = 937.5 e I cresce 58.6 por ciclo, entao a saida chega a 65535 apos ~1100 ciclos (22 us a 50 MHz).

## 3.4 Energy Meter (`energy_meter.vhd`)

### Integracao de energia:

O integrador acumula energia deployada a cada ciclo de clock. Os parametros sao generics: `CLK_HZ` (padrao 50 MHz) e `P_MAX_W` (padrao 120 kW, potencia com duty = 65535).

```
P_deploy = (duty_cycle / 65535) * P_MAX_W
energy_per_clock = P_deploy / CLK_HZ
                 = duty * 1.831 W * 20 ns = duty * 3.662e-8 J  (padrao)

Em kJ com formato Q8 (8 bits fracionarios):
  duty * 3.662e-11 kJ * 256 = duty * 9.375e-9

Acumulador interno com 40 bits fracionarios extras (escala 2^40):
  increment   = duty_cycle * INTEG_SCALE
  INTEG_SCALE = round(9.375e-9 * 2^40) = 10308   (calculado a partir dos generics)

Acumulador interno: 64 bits unsigned
  Bits [63:40] -> saida energy_used (24 bits, kJ em Q8)
  Bits [39:0]  -> fracao para nao perder incrementos pequenos
```

Verificacao: 4 MJ a 120 kW levam 33.3 s, ou seja, 1.67e9 ciclos a 50 MHz.

### Saturacao e reset:

- **Saturacao:** Quando a energia atinge `1024000` (4 MJ em Q8 kJ), o acumulador trava exatamente nesse valor (nunca da a volta).
- **Lap reset:** Pulso de 1 ciclo em `lap_reset` zera o acumulador completamente (tem prioridade sobre o deploy).

### Escala de tempo comprimida (testes):

Com `CLK_HZ = 1000`, cada ciclo de clock vale 1 ms para a integracao. Assim o limite de 4 MJ e atingido em ~33k ciclos, viabilizando testar o corte de energia em simulacao (`tb_energy_meter`, `tb_ers_top`). `ers_top` repassa seu generic `CLK_HZ` ao `energy_meter`. Valor minimo suportado: 1000.

## 3.5 Power Arbiter (`power_arbiter.vhd`)

### Logica de arbitragem:

```
SE deploy_en = '1' E energy < 4 MJ:
    duty_mguk = duty do PI (controle de tracao)
    duty_limited = duty do PI (conta como deploy)
SENAO SE harvest_k_en = '1':
    duty_mguk = 50% fixo (modo gerador)
    duty_limited = 0 (nao conta como deploy)

SE harvest_h_en = '1':
    duty_mguh = 50% fixo
```

### Gerador PWM (50 kHz):

```
Frequencia: 50 MHz / 1000 = 50 kHz
Contador: 0 a 999 (10 bits)
Threshold: duty_16bit * 1000 / 65536 (mapeamento para 0-999)

PWM = '1' quando counter < threshold
PWM = '0' quando counter >= threshold
```

## 3.6 Interconexao no Top-Level (`ers_top.vhd`)

### Logica de setpoint do PI:

O setpoint do controlador PI e derivado do throttle durante deploy:
```
setpoint = throttle & "0000"   (shift left 4 = throttle * 16)
         = throttle(12 bits) -> setpoint(16 bits)
```

O sinal `measured` recebe a porta `p_mguk_meas`, a potencia de deploy medida na planta (0-65535 = 0-120 kW, mesma escala do setpoint). O PI ajusta o duty cycle para que a potencia de tracao acompanhe a demanda do piloto (throttle). Versoes anteriores usavam `speed_rpm` como "proxy", o que deixava a malha efetivamente aberta (ver [capitulo 6](06_cosimulacao_python.md)).

### Generics do top-level:

| Generic | Padrao | Uso |
|---------|--------|-----|
| `CLK_HZ` | 50_000_000 | Escala da integracao de energia |
| `KP`, `KI` | 1024, 64 | Ganhos do PI em Q16, aplicados a cada ciclo |
| `PWM_PERIOD` | 999 | Contador PWM de 0 a `PWM_PERIOD` (50 kHz a 50 MHz) |

### Sinal de feedback:

O `duty_limited` (saida do arbiter) alimenta o `energy_meter`, garantindo que apenas a potencia efetivamente liberada e contabilizada como energia deployada.

## 3.7 Frequencia e Timing

| Parametro | Valor |
|-----------|-------|
| Clock principal | 50 MHz (20 ns) |
| Latencia FSM | 1 ciclo (transicao sincrona) |
| Latencia PI | 1 ciclo (pipeline de 1 estagio) |
| Periodo PWM | 1000 ciclos = 20 us (50 kHz) |
| Reset | Assincrono, ativo em nivel baixo |

A latencia total do pipeline (entrada -> saida PWM) e de 3 ciclos de clock (60 ns), desprezivel em relacao a dinamica da planta (ms).

## 3.8 Testbenches

### tb_ers_fsm — 12 testes:

| # | Teste | Resultado esperado |
|---|-------|--------------------|
| T1 | Reset | STANDBY (000) |
| T2 | Freio forte + SoC ok | HARVESTING_K (001) |
| T3 | Soltar freio | STANDBY (000) |
| T4 | Turbo alto + SoC ok | HARVESTING_H (010) |
| T5 | Acelerador forte | DEPLOYING (011) |
| T6 | SoC muito baixo | FAULT (111) |
| T7 | SoC normaliza | STANDBY (000) |
| T8 | SoC muito alto | FAULT (111) |
| T9 | Freio + acelerador | DEPLOYING (prioridade) |
| T10 | Energia excedida | Nao entra DEPLOYING |
| T11 | SoC > 90% + freio | Nao entra HARVESTING |
| T12 | Transicao HARVEST_K -> HARVEST_H | HARVESTING_H (010) |

### tb_pi_controller — 7 testes:

| # | Teste | Resultado esperado |
|---|-------|--------------------|
| T1 | Reset | duty = 0 |
| T2 | Desabilitado | duty = 0 |
| T3 | Degrau positivo | duty cresce (> 0 apos 1 ciclo, > 50 apos 10) |
| T4 | Erro zero | duty estabiliza |
| T5 | Erro negativo | duty = 0 (saturacao inferior) |
| T6 | Erro muito grande | perto de saturar apos 1000 ciclos; duty = 65535 apos 1200 |
| T7 | Anti-windup | Apos 5000 ciclos saturado, sai da saturacao em 2 ciclos ao inverter o erro e zera apos ~1200 |

### tb_power_arbiter — 7 testes:

| # | Teste | Resultado esperado |
|---|-------|--------------------|
| T1 | Reset | PWM = 0 |
| T2 | Deploy 50% | duty_limited = 32768, PWM oscilando |
| T3 | Energia excedida | duty_limited = 0 |
| T4 | Energia normaliza | duty_limited restaurado |
| T5 | Harvest K | duty_limited = 0 (nao conta) |
| T6 | Harvest H | PWM MGU-H ativo |
| T7 | Tudo desligado | PWM = 0 |

### tb_energy_meter — 8 testes (valores numericos):

Duas instancias com as mesmas entradas: `CLK_HZ = 50 MHz` (escala real) e `CLK_HZ = 1 kHz` (escala comprimida).

| # | Teste | Resultado esperado |
|---|-------|--------------------|
| T1 | Reset | energia = 0 |
| T2 | 30 s a 120 kW (1 kHz) | 3600 kJ = 921600 (Q8) |
| T3 | Passar de 4 MJ (1 kHz) | trava em 1024000 |
| T4 | 250k ciclos | 1 kHz continua em 1024000 (sem wrap); 50 MHz: 5 ms a 120 kW = 153 (Q8) |
| T5 | deploy_en = 0 | energia retida |
| T6 | Lap reset | energia = 0 nas duas instancias |
| T7 | 10 s a 60 kW (1 kHz) | 600 kJ = 153602 (Q8) |
| T8 | Lap reset com deploy ativo | reset tem prioridade |

### tb_ers_top — 9 fases de integracao:

Instanciado com `CLK_HZ = 1000` (escala comprimida) para que o limite de 4 MJ seja alcancavel.

| Fase | Cenario | Verificacao |
|------|---------|-------------|
| F1 | Standby | ers_mode=000, fault=0 |
| F2 | Aceleracao | DEPLOYING, PWM oscila, energia entre 1 e 4 MJ |
| F3 | Frenagem | HARVESTING_K, PWM oscila, energia de deploy nao muda |
| F4 | Turbo alto | HARVESTING_H |
| F5 | SoC baixo | FAULT |
| F6 | Recuperacao | STANDBY |
| F7 | Lap reset | Energia zera |
| F8 | Deploy continuo | Energia trava em 4 MJ, FSM sai de DEPLOYING, PWM desligado |
| F9 | Nova volta | lap_reset libera DEPLOYING novamente |

## 3.9 Como Executar

### Com GHDL (livre, recomendado)

```bash
./scripts/run_tests.sh                 # compila e roda todos os testbenches
./scripts/run_tests.sh tb_energy_meter # apenas um
```

O script falha (codigo != 0) se qualquer `assert ... severity error` disparar ou se um testbench nao terminar sozinho. O mesmo script roda no GitHub Actions a cada push (`.github/workflows/vhdl-tests.yml`).

### Com ModelSim

```
# No ModelSim, a partir da pasta scripts/:
do compile_all.do        # Compila tudo
do sim_standalone.do     # Roda todos os testbenches
```

Para rodar um testbench individual:
```
do compile_all.do
vsim -t ns work.tb_ers_fsm
run -all
```
