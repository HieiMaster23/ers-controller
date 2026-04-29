# 2. Modelo Fisico — Simulink

## 2.1 Visao Geral

O modelo fisico representa a planta do sistema ERS: os componentes eletricos e mecanicos do trem de forca que o controlador VHDL ira gerenciar. O modelo e implementado em Simulink e dividido em quatro subsistemas:

```
+-------------------------------------------------------------------+
|                   vehicle_model.slx                               |
|                                                                   |
|  +-----------------+                                              |
|  | Race_Scenario   |--speed_rpm--->+---------------+              |
|  | (Gerador de     |--brake_pres-->| MGU_K         |--I_mguk--+  |
|  |  cenario)       |--throttle---->| (Frenagem)    |--P_mguk  |  |
|  |                 |--turbo_rpm-+  +---------------+           |  |
|  +-----------------+            |                              |  |
|                                 |  +---------------+           |  |
|                                 +->| MGU_H         |--I_mguh--+  |
|                                    | (Turbo)       |--P_mguh  |  |
|                                    +---------------+           |  |
|                                                                |  |
|                                    +---------------+           |  |
|                                    | Battery_HV    |<----------+  |
|                                    | (Bateria RC)  |              |
|                                    |               |-->soc_adc    |
|                                    |               |-->soc_%      |
|                                    |               |-->V_term     |
|                                    +---------------+              |
+-------------------------------------------------------------------+
```

## 2.2 Equacoes do Modelo

### 2.2.1 MGU-K (Motor Generator Unit — Kinetic)

O MGU-K converte energia cinetica de frenagem em energia eletrica. O modelo simplificado usa:

```
Torque_k = K_mguk * brake_bar                [Nm]
omega    = speed_rpm * 2*pi / 60             [rad/s]
P_mech   = Torque_k * omega                  [W]
P_elec   = P_mech * eta_mguk                 [W]
P_mguk   = min(P_elec, P_max_mguk)           [W]  (saturacao em 120 kW)
I_mguk   = P_mguk / V_bus                    [A]
```

Onde:
- `brake_bar = brake_pres_adc * 100 / 4095` (conversao ADC para bar)
- `K_mguk = 0.8 Nm/bar` (constante de torque simplificada)
- `eta_mguk = 0.90` (rendimento de conversao)

### 2.2.2 MGU-H (Motor Generator Unit — Heat)

O MGU-H recupera energia dos gases de escapamento via turbocompressor. Potencia proporcional ao quadrado da RPM do turbo:

```
P_turbo = k_turbo * turbo_rpm^2              [W]
P_mguh  = min(P_turbo, P_max_mguh)           [W]  (saturacao em 50 kW)
I_mguh  = P_mguh / V_bus                     [A]
```

Onde:
- `k_turbo = 1.5e-8 W/RPM^2`
- A relacao quadratica reflete a dependencia da potencia aerodinamica com a velocidade de rotacao

### 2.2.3 Bateria HV — Modelo RC de 1a Ordem

A bateria e modelada como um circuito RC simples (fonte de tensao + resistencia interna):

```
Equacao de estado:
  dSoC/dt = I_total / Q_max_As

Onde:
  Q_max_As = Q_max_battery / V_bus_nominal = 4e6 / 400 = 10000 As
  I_total  = I_mguk + I_mguh    (corrente positiva = carga)

Tensao terminal:
  V_terminal = V_oc - R_internal * I_total

Limites do integrador:
  0.20 <= SoC <= 0.95  (clamping por saturacao)
```

A tensao de circuito aberto `V_oc` e simplificada como constante (`V_bus_nominal = 400V`), desprezando a variacao com SoC que ocorre em baterias reais.

Conversao para interface digital:
```
soc_adc = SoC * 4095   (0.0-1.0 -> 0-4095, 12 bits)
```

### 2.2.4 Cenario de Corrida

O cenario simula uma volta de 60 segundos com quatro trechos distintos, usando lookup tables com interpolacao linear:

| Trecho | Tempo | speed_rpm | brake | throttle | turbo_rpm |
|--------|-------|-----------|-------|----------|-----------|
| Aceleracao | 0-28s | 3k -> 18k | 0 | 2048 -> 4095 | 20k -> 65k |
| Frenagem | 28-36s | 18k -> 5k | 0 -> 4095 -> 2k | 4095 -> 0 | 65k -> 20k |
| Curva | 36-45s | 5k -> 8k | 0 | 500 -> 2500 | 25k -> 40k |
| Saida de curva | 45-60s | 8k -> 3k* | 0 | 2500 -> 2048 | 40k -> 20k |

(*) Volta ao valor inicial para continuidade ciclica.

O sinal de tempo e tornado ciclico usando operacao modulo: `t_lap = mod(t, T_volta)`.

## 2.3 Parametros Utilizados

| Parametro | Valor | Unidade | Justificativa |
|-----------|-------|---------|---------------|
| `V_bus_nominal` | 400 | V | Tensao tipica do barramento HV em F1 |
| `Q_max_battery` | 4e6 | J | Capacidade de energia definida pelo regulamento |
| `SoC_inicial` | 0.70 | - | 70%: valor realista de inicio de corrida |
| `R_internal` | 0.05 | Ohm | Resistencia tipica de pack HV de alta performance |
| `K_mguk_torque` | 0.8 | Nm/bar | Simplificacao linear da curva torque-pressao |
| `P_max_mguk` | 120e3 | W | Limite regulamentar (120 kW) |
| `eta_mguk` | 0.90 | - | Rendimento tipico de maquina PMSM |
| `k_turbo` | 1.5e-5 | W/RPM^2 | Calibrado para ~50 kW @ 58000 RPM (ajustado de 1.5e-8 que produzia potencia desprezivel) |
| `P_max_mguh` | 50e3 | W | Limite pratico do MGU-H em F1 |
| `T_volta` | 60 | s | Volta simplificada (circuitos reais: 70-100s) |
| `Ts` | 1e-3 | s | Passo de 1ms: suficiente para dinamica do modelo |

## 2.4 Simplificacoes Adotadas

### Em relacao ao MGU-K real:
- **Torque linear com pressao de freio:** Na realidade, a curva torque-velocidade de uma PMSM e nao-linear e depende da estrategia de controle de campo. Aqui usamos relacao linear direta.
- **Rendimento constante:** O rendimento real varia com ponto de operacao (velocidade e torque). Adotamos eta fixo de 90%.
- **Sem inercia mecanica:** Nao modelamos a dinamica mecanica do acoplamento (seria um Transfer Function de 1a ou 2a ordem).

### Em relacao ao MGU-H real:
- **Modelo DC simplificado:** O MGU-H real e uma maquina sincrona de alta velocidade acoplada ao turbo. Aqui modelamos como potencia proporcional ao quadrado da RPM.
- **Sem dinamica de gases:** Nao modelamos a termodinamica dos gases de escape nem a dinamica do turbocompressor.

### Em relacao a bateria real:
- **V_oc constante:** Na realidade, a tensao de circuito aberto varia significativamente com o SoC (curva OCV). Adotamos V_oc = 400V constante.
- **Sem efeitos termicos:** Nao modelamos aquecimento, degradacao, ou variacao de resistencia com temperatura.
- **Modelo RC de 1a ordem:** Baterias reais requerem pelo menos 2a ordem (RC duplo) para capturar as dinamicas de relaxacao.

### Em relacao ao cenario:
- **Volta simplificada de 60s:** Voltas reais duram 70-100s com perfis mais complexos.
- **Sem variacao entre voltas:** Cada volta e identica (mesmo perfil). Em corrida real, desgaste de pneus e combustivel alteram o perfil.

## 2.5 Comportamento Esperado na Validacao Standalone

Ao executar `validate_standalone.m`, o modelo simula 3 voltas (180s) apenas com harvest (sem deploy, pois o controlador VHDL ainda nao esta integrado):

1. **SoC:** Deve subir progressivamente a cada volta, pois so ha harvest. Partindo de 70%, espera-se atingir o limite de 95% durante a 2a ou 3a volta, onde o integrador satura.

2. **P_mguk:** Picos durante frenagem (~28-36s de cada volta). Deve respeitar o limite de 120 kW. Valor maximo esperado: ~80 kW (limitado pelo cenario, nao pela saturacao).

3. **P_mguh:** Ativa quando turbo_rpm > 40000 RPM, ou seja, durante aceleracao forte. Picos esperados: ~40-50 kW.

4. **Correntes:** I_total durante harvest nao deve ultrapassar 300A (120kW / 400V = 300A).

5. **Tensao terminal:** Deve permanecer proxima de 400V, com queda de ate ~15V durante picos de corrente (300A * 0.05 Ohm = 15V).

## 2.6 Como Executar

### Gerar o modelo Simulink:
```matlab
cd simulink/
create_vehicle_model   % Gera vehicle_model.slx
```

### Rodar validacao standalone (MATLAB puro):
```matlab
cd simulink/
validate_standalone    % Simula 3 voltas e plota graficos
```

### Rodar no Simulink:
```matlab
cd simulink/
create_vehicle_model   % Gera o modelo
sim('vehicle_model')   % Simula
% Dados exportados: soc_data, p_mguk_data, p_mguh_data (timeseries)
```
