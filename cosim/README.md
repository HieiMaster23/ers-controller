# Co-simulacao VHDL + planta Python

O controlador VHDL real (`vhdl/`) roda no GHDL em malha fechada com uma planta fisica em Python, via cocotb. Nao precisa de MATLAB nem ModelSim.

```bash
sudo apt-get install ghdl
pip install -r cosim/requirements.txt
python cosim/run_cosim.py        # roda os testes (~2 min)
python cosim/plot_results.py     # gera cosim/results/race_3_laps.png
```

| Arquivo | Funcao |
|---------|--------|
| `plant.py` | Planta: perfil de volta, MGU-K, MGU-H, bateria (Python puro) |
| `hdl/ers_cosim_wrapper.vhd` | Envolve `ers_top`: clock interno e medidores de duty do PWM |
| `test_ers_cosim.py` | Acoplamento planta <-> VHDL e testes cocotb |
| `run_cosim.py` | Compila com GHDL e roda os testes |
| `plot_results.py` | Graficos a partir dos CSVs de `results/` |

Detalhes, resultados e limitacoes: [docs/06_cosimulacao_python.md](../docs/06_cosimulacao_python.md).
