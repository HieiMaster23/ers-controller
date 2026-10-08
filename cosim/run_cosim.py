#!/usr/bin/env python3
"""Compila o VHDL com GHDL e roda a co-simulacao cocotb.

Uso:
    python cosim/run_cosim.py                     # todos os testes
    python cosim/run_cosim.py test_race_3_laps    # apenas um

Os CSVs de resultado ficam em cosim/results/ (gerar graficos com
python cosim/plot_results.py).
"""

import sys
from pathlib import Path

from cocotb_tools.runner import get_runner

COSIM = Path(__file__).resolve().parent
ROOT = COSIM.parent

# O runner repassa o sys.path deste processo como PYTHONPATH do simulador:
# garantir que os modulos de cosim/ (testes e planta) sejam encontrados.
sys.path.insert(0, str(COSIM))

SOURCES = [
    ROOT / "vhdl" / "ers_fsm.vhd",
    ROOT / "vhdl" / "pi_controller.vhd",
    ROOT / "vhdl" / "power_arbiter.vhd",
    ROOT / "vhdl" / "energy_meter.vhd",
    ROOT / "vhdl" / "ers_top.vhd",
    COSIM / "hdl" / "ers_cosim_wrapper.vhd",
]


def main() -> int:
    runner = get_runner("ghdl")
    build_dir = ROOT / "build" / "cosim"
    runner.build(
        sources=SOURCES,
        hdl_toplevel="ers_cosim_wrapper",
        build_args=["--std=08"],
        build_dir=build_dir,
        always=True,
    )
    results = runner.test(
        test_module="test_ers_cosim",
        hdl_toplevel="ers_cosim_wrapper",
        build_dir=build_dir,
        testcase=sys.argv[1:] or None,
        test_args=["--std=08"],
        plusargs=["--ieee-asserts=disable-at-0"],
    )
    # Falha se algum teste falhou
    from cocotb_tools.check_results import get_results
    _, failed = get_results(results)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
