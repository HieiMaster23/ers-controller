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
  |  speed_rpm ---> [            ]     duty_limited   |      |
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

O controlador PI opera inteiramente em aritmetica de ponto fixo Q16 (16 bits inteiros, 16 bits fracionarios, 32 bits total signed).

```
Formato Q16.16 (signed 32 bits):
  Bit 31      = sinal
  Bits 30..16 = parte inteira (15 bits) -> faixa -32768 a +32767
  Bits 15..0  = parte fracionaria (16 bits) -> resolucao 1/65536 = 1.53e-5

Exemplo: KP = 1024 em Q16 = 1024 / 65536 = 0.015625
         KI = 64 em Q16   = 64 / 65536   = 0.000977
```

### Algoritmo:

```
A cada ciclo de clock (se enable = '1'):
  1. error = setpoint - measured         (signed 17 bits)
  2. p_term = KP * error                 (signed 32 bits, Q16)
  3. i_accum += KI * error               (signed 32 bits, Q16, com clamping)
  4. pi_sum = p_term + i_accum           (signed 32 bits)
  5. output = pi_sum >> 16               (converter Q16 -> inteiro)
  6. duty_out = saturate(output, 0, 65535)
```

### Anti-windup:

O acumulador integral e limitado por clamping:
- `INTEG_MAX = OUT_MAX * 256 = 16776960`
- `INTEG_MIN = 0`

Se `i_accum + KI*error` exceder esses limites, o acumulador trava no limite. Isso evita que o integrador "carregue" excessivamente durante saturacao, permitindo resposta rapida quando o erro muda de sinal.

### Resposta esperada:

Com KP=0.015625 e KI=0.000977, para um degrau de erro=5000:
- P imediato: 0.015625 * 5000 = 78.125
- I apos 10 ciclos: 0.000977 * 5000 * 10 = 48.8
- Total apos 10 ciclos: ~127 (saida deve ser > 50, criterio de aceitacao)

## 3.4 Energy Meter (`energy_meter.vhd`)

### Integracao de energia:

O integrador acumula energia deployada a cada ciclo de clock:

```
P_deploy = (duty_cycle / 65535) * 120000 W
energy_per_clock = P_deploy * dt = P_deploy * 20 ns

Em unidades de kJ com formato Q8 (8 bits fracionarios):
  increment = duty_cycle * INTEG_SCALE
  INTEG_SCALE = round(9.375e-6 * 2^24) = 157

Acumulador interno: 40 bits unsigned
  Bits [39:16] -> saida energy_used (24 bits, kJ em Q8)
  Bits [15:0]  -> fracao adicional para precisao
```

### Saturacao e reset:

- **Saturacao:** Quando `energy_used >= 1024000` (4 MJ em Q8 kJ), o acumulador trava.
- **Lap reset:** Pulso de 1 ciclo em `lap_reset` zera o acumulador completamente.

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

O sinal `measured` recebe `speed_rpm` como proxy de potencia entregue. O PI ajusta o duty cycle para que a potencia de tracao acompanhe a demanda do piloto (throttle).

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
| T6 | Erro muito grande | duty = 65535 (saturacao superior) |
| T7 | Anti-windup | Recuperacao rapida apos inversao |

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

### tb_ers_top — 7 fases de integracao:

| Fase | Cenario | Verificacao |
|------|---------|-------------|
| F1 | Standby | ers_mode=000, fault=0 |
| F2 | Aceleracao | DEPLOYING, energia acumula |
| F3 | Frenagem | HARVESTING_K |
| F4 | Turbo alto | HARVESTING_H |
| F5 | SoC baixo | FAULT |
| F6 | Recuperacao | STANDBY |
| F7 | Lap reset | Energia zera |

## 3.9 Como Executar

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
