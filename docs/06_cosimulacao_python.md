# 6. Co-simulacao com Planta Python (GHDL + cocotb)

## 6.1 Motivacao

A co-simulacao da etapa 4 depende de MATLAB, Simulink, HDL Verifier e ModelSim. Sem a licenca do HDL Verifier, os resultados vinham de um **controlador placeholder** escrito em Simulink, e o VHDL nunca rodava em malha fechada com a planta.

Esta etapa fecha a malha com ferramentas livres:

- **GHDL** simula o RTL real (`vhdl/*.vhd`, sem alteracoes de logica)
- **cocotb** conecta o simulador ao Python
- **`cosim/plant.py`** reimplementa a planta de `simulink/create_vehicle_model.m` (mesmos parametros e mesmo perfil de volta)

Tudo roda com `pip install` e `apt install`, inclusive no GitHub Actions a cada push.

## 6.2 Arquitetura

```
+----------------------------------+        +-------------------------------------+
|  Python (cosim/)                 |  VPI   |  GHDL                               |
|                                  | <----> |  ers_cosim_wrapper.vhd              |
|  RaceScenario  -> speed, brake,  |        |   +-- clock interno (5 kHz)         |
|                   throttle,turbo |------->|   +-- ers_top.vhd  (RTL real)       |
|  ErsPlant      -> soc_in,        |------->|   |    FSM, PI, arbiter, energy     |
|                   p_mguk_meas    |        |   +-- medidores de duty do PWM      |
|                                  |<-------|        (conta ciclos em '1')        |
|  le: ers_mode, duty_k, duty_h,   |        |                                     |
|      energy_used                 |        |                                     |
+----------------------------------+        +-------------------------------------+
```

A cada passo de **20 ms**:

1. A planta escreve no VHDL os sinais do carro, o SoC e a potencia de deploy medida.
2. O GHDL roda 100 ciclos de clock, ou seja, um periodo completo de PWM.
3. O Python le o modo da FSM, a energia da volta e o duty medido de cada PWM.
4. A planta integra a fisica com esse comando.

Na fronteira de cada volta (60 s), o Python pulsa `lap_reset` por um ciclo.

### Escala de tempo

| Parametro | Hardware alvo | Co-simulacao |
|-----------|---------------|--------------|
| Clock do controlador | 50 MHz | 5 kHz |
| Periodo do PWM | 1000 contagens = 20 us | 100 contagens = 20 ms |
| Passo da planta | - | 20 ms |

O RTL e o mesmo; mudam so os generics (`CLK_HZ`, `PWM_PERIOD`). O clock baixo e necessario porque o GHDL fica muito mais lento quando controlado via VPI (cerca de 1 s real por segundo simulado com 5 kHz).

**Atencao:** os ganhos do PI (`KP`, `KI`) sao aplicados a cada ciclo de clock. Em 5 kHz o integrador tem constante de tempo de algumas centenas de ms, adequada para a planta. Em 50 MHz o mesmo ganho seria 10000 vezes mais rapido, entao uma implementacao em FPGA precisa de um divisor de taxa para o PI (atualizar a cada N ciclos).

## 6.3 Mudancas no RTL para fechar a malha

| Mudanca | Motivo |
|---------|--------|
| Nova porta `p_mguk_meas` em `ers_top` (0-65535 = 0-120 kW) | O PI comparava o setpoint (`throttle*16`) com `speed_rpm`, grandezas diferentes: o erro ficava sempre positivo e o duty ia a 100% (malha aberta). Agora o valor medido e a potencia de deploy. |
| `speed_rpm` passa a ser reservado (nao usado) | Mantido na interface para compatibilidade com o modelo Simulink. |
| Generics `KP`, `KI`, `PWM_PERIOD` em `ers_top`; `PWM_PERIOD` em `power_arbiter` | Permitem reescalar o controlador (co-simulacao, e no futuro o carrinho). Os padroes mantem o comportamento original. |

A energia da volta continua sendo integrada a partir do **duty comandado** (`duty_limited`). Como a tensao da bateria cai sob carga, a potencia real e menor que a comandada; o corte de 4 MJ fica conservador (a energia real entregue na volta fica um pouco abaixo de 4 MJ).

## 6.4 Modelo da planta (`cosim/plant.py`)

Mesmas equacoes e parametros do capitulo 2, com tres diferencas:

1. **O harvest e comandado pelo controlador.** O MGU-K so recupera em `HARVESTING_K` e o MGU-H so em `HARVESTING_H`. No Simulink a planta recuperava sempre, independente da FSM.
2. **O deploy segue o PWM.** Potencia comandada = `duty * 120 kW * (V_terminal / 400 V)`, com dinamica de 1a ordem do inversor (`tau = 20 ms`).
3. **A tensao terminal cai com a corrente** (`R_int = 0.05 Ohm`). Com 300 A a queda e de 15 V, entao o PI precisa de mais duty para entregar a potencia pedida.

## 6.5 Testes

`cosim/test_ers_cosim.py` tem tres testes com verificacoes automaticas:

| Teste | Cenario | Verifica |
|-------|---------|----------|
| `test_pi_tracking` | Acelerador constante em 73% | A potencia entregue converge para 87.9 kW (alvo = 73% de 120 kW) com erro < 2%, e o duty fica acima de 73% (compensando a queda de tensao). |
| `test_lap_energy_limit` | Acelerador 100% continuo; bateria grande para isolar o limite do regulamento | O VHDL trava em 4.000 MJ e corta o deploy entre 32 e 36 s; a energia real da volta fica entre 3.8 e 4.0 MJ; o deploy volta apos `lap_reset`. |
| `test_race_3_laps` | Perfil de volta padrao, 3 voltas | Sem FAULT; passa por deploy, harvest K e harvest H; deploy <= 4 MJ/volta; potencia <= 120 kW; SoC em [20%, 95%]. |

## 6.6 Resultados

Corrida de 3 voltas com o controlador VHDL real:

| Volta | Deploy entregue | Harvest | Energia medida pelo VHDL | SoC no fim |
|-------|-----------------|---------|--------------------------|------------|
| 1 | 2.81 MJ | 1.01 MJ | 2.90 MJ | 25.0% |
| 2 | 1.33 MJ | 1.33 MJ | 1.36 MJ | 25.0% |
| 3 | 1.33 MJ | 1.33 MJ | 1.36 MJ | 25.0% |

Outros resultados:

- PI: rastreia 87.9 kW e entra na faixa de 2% em 0.74 s.
- Deploy pico: 114.5 kW. A queda de tensao impede chegar a 120 kW mesmo com duty de 100%.
- Teste de limite: corte em 33.5 s, com 3.82 MJ entregues e 4.00 MJ contabilizados.

![Co-simulacao de 3 voltas](img/cosim_race.png)

### O que a simulacao mostra

1. **O carro fica "sem bateria" a partir da volta 2.** A primeira volta gasta a carga inicial (70% -> 25%). Depois disso o controlador so consegue gastar o que recupera (~1.3 MJ por volta), bem abaixo do limite de 4 MJ. O resultado anterior (3.82 MJ/volta) vinha do placeholder, cuja planta recuperava energia mesmo quando a FSM nao mandava.

2. **A FSM oscila no limite de SoC (chattering).** Com o SoC parado em 25%, o controlador alterna entre `DEPLOYING` e `HARVESTING_H` a cada poucos passos: o deploy baixa o SoC para menos de 25%, o harvest sobe de volta, e o ciclo se repete (faixas listradas no grafico). Os limiares de SoC nao tem histerese.

3. **Pico de potencia ao reentrar em deploy.** O PI mantem o integrador quando e desabilitado. Ao voltar para `DEPLOYING`, ele parte do valor antigo e a potencia da um salto (picos de ~100 kW em t = 43, 103 e 163 s) antes de convergir.

4. **O MGU-H nunca recupera durante o deploy.** Os estados da FSM sao exclusivos. No ERS real (regras 2014-2025), o MGU-H podia alimentar o MGU-K diretamente durante a aceleracao.

Os itens 2 e 3 sao comportamentos do RTL que os testbenches isolados nao mostravam. Ficam como proximos passos de projeto.

## 6.7 Como executar

```bash
sudo apt-get install ghdl
pip install -r cosim/requirements.txt

python cosim/run_cosim.py                    # 3 testes (~2 min)
python cosim/run_cosim.py test_pi_tracking   # apenas um
python cosim/plot_results.py                 # grafico da corrida
```

Os CSVs (uma linha a cada 100 ms, ou 20 ms no teste do PI) ficam em `cosim/results/` e podem ser abertos em qualquer planilha. As colunas incluem pedais, modo da FSM, duty, potencias, SoC, tensao terminal e energia da volta.
