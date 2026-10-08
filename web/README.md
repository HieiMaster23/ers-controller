# ERS ao vivo (painel web)

Painel interativo para quem tem curiosidade sobre o ERS: o visitante pilota (ou assiste à volta de referência) e vê, em tempo real, o que o controlador decide e por quê.

Abrir: dê dois cliques em `web/index.html`. Não precisa de servidor nem de instalação; funciona em qualquer navegador e no celular.

## O que a página mostra

- **Fluxo de energia no carro**: setas animadas entre MGU-K, MGU-H e bateria. Quando o carro freia sem recuperar (bateria cheia), os freios dianteiros "esquentam".
- **O que o controlador decidiu**: o estado da FSM (`ers_mode`), com uma frase explicando o motivo. Por exemplo, "deploy bloqueado até a bateria chegar a 30%" ou "limite de 4 MJ desta volta atingido".
- **Bateria e regulamento**: SoC com os limiares de histerese, energia de deploy da volta contra o limite de 4 MJ, potências, velocidade e turbo.
- **Gráficos dos últimos 30 s** (potência e SoC), com valores ao passar o mouse.
- **Voltas**: tempo, energia gasta e recuperada por volta. Pilotando, dá para ver que o deploy encurta a volta.
- **Laboratório**: desliga a histerese ou a partida suave do PI para ver os problemas que a co-simulação revelou. Também permite mudar a carga inicial da bateria.

Controles: botões Acelerar e Frear (segurar), ou as teclas ↑/W e ↓/espaço.

## Como funciona

| Arquivo | Conteúdo |
|---------|----------|
| `ers_model.js` | Emulação ciclo a ciclo do RTL (FSM com histerese, PI em ponto fixo com partida suave, PWM, medidor de energia e medidores de duty do wrapper), porta da planta de `cosim/plant.py` e um modelo simples de carro para o modo manual |
| `app.js` | Laço de simulação, explicações, gráficos e controles |
| `index.html` | Layout e estilos (temas claro e escuro) |
| `test/compare_with_vhdl.js` | Compara o modelo com a co-simulação do VHDL real |

O controlador roda na mesma escala de tempo da co-simulação: clock de 5 kHz, PWM de 100 contagens e passo de planta de 20 ms, ou seja, 100 ciclos de clock emulados por passo.

## Fidelidade ao VHDL

O CI roda a corrida de 3 voltas no GHDL (`cosim/run_cosim.py`) e depois:

```bash
node web/test/compare_with_vhdl.js cosim/results/race_3_laps.csv
```

O teste compara as 1800 amostras do CSV com o modelo JS. O modo da FSM precisa bater em 100% das amostras; SoC, potência, duty e energia precisam bater dentro do arredondamento do CSV. Resultado atual: 100% do modo, SoC com diferença máxima de 0,0005 p.p. Se alguém mudar o VHDL sem atualizar o painel (ou o contrário), o CI falha.

O modo manual usa um modelo de carro simplificado (aceleração, frenagem, arrasto e turbo de 1ª ordem). Ele não faz parte da comparação, que usa a volta de referência.

## Publicar

A pasta é estática. Para publicar no GitHub Pages, aponte o Pages para a pasta `web/` (ou copie os três arquivos para qualquer hospedagem estática).
