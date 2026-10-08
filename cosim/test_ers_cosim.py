"""Co-simulacao do controlador ERS (VHDL real, via GHDL) com a planta Python.

Cada passo de 20 ms:
  1. a planta escreve os sinais do carro e o SoC/potencia medida no VHDL;
  2. o simulador VHDL roda 100 ciclos de clock (1 periodo de PWM);
  3. o Python le o modo da FSM, a energia e o duty medido do PWM;
  4. a planta integra a fisica com esse comando.

Executar: python cosim/run_cosim.py   (ver cosim/README.md)
"""

from __future__ import annotations

import csv
import os
from dataclasses import dataclass, field
from pathlib import Path

import cocotb
from cocotb.triggers import Timer

from plant import (
    DEPLOYING,
    FAULT,
    HARVESTING_H,
    HARVESTING_K,
    MODE_NAMES,
    ConstantScenario,
    DriverInputs,
    ErsPlant,
    PlantParams,
    RaceScenario,
)

STEP_US = 20_000              # passo da planta: 20 ms
CLK_US = 200                  # clock do controlador na co-simulacao: 5 kHz
PWM_COUNTS = 100              # PWM_PERIOD + 1 (ver ers_cosim_wrapper.vhd)
ENERGY_MAX_Q8 = 1024000       # 4 MJ em kJ Q8
P_SCALE_W = 120e3             # 65535 em throttle*16 / p_mguk_meas = 120 kW

RESULTS_DIR = Path(os.environ.get("ERS_RESULTS_DIR",
                                  Path(__file__).parent / "results"))


@dataclass
class LapSummary:
    lap: int
    e_deploy_mj: float
    e_harvest_mj: float
    e_vhdl_mj: float
    soc_end: float


@dataclass
class CosimRun:
    """Acopla o DUT (ers_cosim_wrapper) a uma planta e um cenario."""

    dut: object
    plant: ErsPlant
    scenario: object
    rows: list = field(default_factory=list)
    laps: list = field(default_factory=list)
    modes_seen: set = field(default_factory=set)
    mode_changes: int = 0         # trocas de ers_mode (amostradas a cada passo)
    max_excess_kw: float = 0.0    # maior (potencia entregue - setpoint) em deploy
    t: float = 0.0
    _last_mode: int | None = None

    async def reset(self) -> None:
        dut = self.dut
        self._write_inputs(self.scenario.at(0.0))
        dut.lap_reset.value = 0
        dut.rst_n.value = 0
        await Timer(1, unit="ms")
        dut.rst_n.value = 1

    def _write_inputs(self, inp: DriverInputs) -> None:
        dut = self.dut
        dut.speed_rpm.value = inp.speed_rpm
        dut.brake_pres.value = inp.brake_adc
        dut.throttle.value = inp.throttle_adc
        dut.turbo_rpm.value = inp.turbo_rpm
        dut.soc_in.value = self.plant.soc_adc
        dut.p_mguk_meas.value = self.plant.p_meas_adc

    def energy_vhdl_mj(self) -> float:
        return self.dut.energy_used.value.to_unsigned() / 256.0 / 1000.0

    async def run(self, duration_s: float, log_every: int = 5) -> None:
        """Avanca duration_s segundos; registra 1 linha a cada log_every passos."""
        dut = self.dut
        dt = STEP_US * 1e-6
        steps_per_lap = round(self.scenario.lap_time / dt)
        n_steps = round(duration_s / dt)
        step0 = round(self.t / dt)

        for k in range(step0, step0 + n_steps):
            self.t = k * dt
            inp = self.scenario.at(self.t)

            # Fronteira de volta: registrar resumo e pulsar lap_reset
            new_lap = k > 0 and k % steps_per_lap == 0
            if new_lap:
                self._close_lap(k // steps_per_lap)
                self.plant.new_lap()

            self._write_inputs(inp)
            if new_lap:
                dut.lap_reset.value = 1
                await Timer(CLK_US, unit="us")
                dut.lap_reset.value = 0
                await Timer(STEP_US - CLK_US, unit="us")
            else:
                await Timer(STEP_US, unit="us")

            mode = dut.ers_mode.value.to_unsigned()
            duty_k = dut.duty_k_cnt.value.to_unsigned() / PWM_COUNTS
            duty_h = dut.duty_h_cnt.value.to_unsigned() / PWM_COUNTS
            self.modes_seen.add(mode)
            if self._last_mode is not None and mode != self._last_mode:
                self.mode_changes += 1
            self._last_mode = mode
            self.plant.step(dt, inp, mode, duty_k, duty_h)
            if mode == DEPLOYING:
                setpoint_w = inp.throttle_adc * 16 / 65535 * P_SCALE_W
                self.max_excess_kw = max(
                    self.max_excess_kw, (self.plant.p_deploy - setpoint_w) / 1e3)

            if k % log_every == 0:
                self.rows.append({
                    "t_s": round(self.t + dt, 3),
                    "throttle_pct": round(inp.throttle_adc / 40.95, 1),
                    "brake_pct": round(inp.brake_adc / 40.95, 1),
                    "speed_rpm": inp.speed_rpm,
                    "turbo_rpm": inp.turbo_rpm,
                    "mode": MODE_NAMES.get(mode, str(mode)),
                    "mode_code": mode,
                    "duty_k": duty_k,
                    "duty_h": duty_h,
                    "p_setpoint_kw": round(
                        inp.throttle_adc * 16 / 65535 * P_SCALE_W / 1e3, 2)
                        if mode == DEPLOYING else 0.0,
                    "p_deploy_kw": round(self.plant.p_deploy / 1e3, 2),
                    "p_harv_k_kw": round(self.plant.p_harv_k / 1e3, 2),
                    "p_harv_h_kw": round(self.plant.p_harv_h / 1e3, 2),
                    "soc_pct": round(self.plant.soc * 100, 3),
                    "v_term": round(self.plant.v_term, 2),
                    "e_lap_deploy_mj": round(self.plant.e_lap_deploy / 1e6, 4),
                    "e_vhdl_mj": round(self.energy_vhdl_mj(), 4),
                })

        self.t = (step0 + n_steps) * dt

    def _close_lap(self, lap_number: int) -> None:
        self.laps.append(LapSummary(
            lap=lap_number,
            e_deploy_mj=self.plant.e_lap_deploy / 1e6,
            e_harvest_mj=self.plant.e_lap_harvest / 1e6,
            e_vhdl_mj=self.energy_vhdl_mj(),
            soc_end=self.plant.soc,
        ))

    def save_csv(self, name: str) -> Path:
        RESULTS_DIR.mkdir(parents=True, exist_ok=True)
        path = RESULTS_DIR / f"{name}.csv"
        with path.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(self.rows[0].keys()))
            writer.writeheader()
            writer.writerows(self.rows)
        return path


def _window(rows: list, t0: float, t1: float) -> list:
    return [r for r in rows if t0 <= r["t_s"] <= t1]


# ============================================================================
# Testes
# ============================================================================

@cocotb.test()
async def test_pi_tracking(dut):
    """O MGU-K entrega a fracao de potencia pedida pelo acelerador."""
    throttle = 3000  # 73% -> setpoint = 3000*16/65535 * 120 kW = 87.9 kW
    scenario = ConstantScenario(DriverInputs(
        speed_rpm=12000, brake_adc=0, throttle_adc=throttle, turbo_rpm=0))
    run = CosimRun(dut, ErsPlant(), scenario)
    await run.reset()
    await run.run(3.0, log_every=1)
    run.save_csv("pi_tracking")

    target_kw = throttle * 16 / 65535 * P_SCALE_W / 1e3
    tail = _window(run.rows, 2.0, 3.0)
    mean_kw = sum(r["p_deploy_kw"] for r in tail) / len(tail)
    settle = next((r["t_s"] for r in run.rows
                   if abs(r["p_deploy_kw"] - target_kw) < 0.02 * target_kw),
                  None)
    dut._log.info("PI: alvo %.1f kW, media em regime %.1f kW, "
                  "entra na faixa de 2%% em t = %s s", target_kw, mean_kw, settle)

    assert all(r["mode_code"] == DEPLOYING for r in tail), "deveria estar em deploy"
    assert abs(mean_kw - target_kw) < 0.02 * target_kw, (
        f"PI nao rastreia o setpoint: {mean_kw:.1f} kW vs {target_kw:.1f} kW")
    # A tensao da bateria cai sob carga, entao o duty precisa ficar acima
    # da fracao pedida: e o PI compensando a queda
    assert tail[-1]["duty_k"] > throttle * 16 / 65535, (
        "duty deveria compensar a queda de tensao da bateria")


@cocotb.test()
async def test_lap_energy_limit(dut):
    """Deploy continuo e cortado em 4 MJ e liberado na volta seguinte."""
    # Bateria grande para isolar o limite do regulamento do limite de SoC
    params = PlantParams(e_bat=40e6, soc0=0.60)
    scenario = ConstantScenario(DriverInputs(
        speed_rpm=15000, brake_adc=0, throttle_adc=4095, turbo_rpm=0))
    run = CosimRun(dut, ErsPlant(params), scenario)
    await run.reset()
    await run.run(62.0)
    run.save_csv("lap_energy_limit")

    lap1 = run.laps[0]
    cut = next(r["t_s"] for r in run.rows if r["mode_code"] != DEPLOYING)
    dut._log.info("Volta 1: deploy %.3f MJ (planta), %.3f MJ (VHDL), "
                  "corte em t = %.2f s", lap1.e_deploy_mj, lap1.e_vhdl_mj, cut)

    assert lap1.e_vhdl_mj == ENERGY_MAX_Q8 / 256 / 1000, "VHDL deveria travar em 4 MJ"
    # O VHDL integra o duty comandado (>= potencia real, por causa da queda
    # de tensao): o corte e conservador, a energia real fica <= 4 MJ
    assert 3.8 <= lap1.e_deploy_mj <= 4.0, (
        f"energia real da volta fora do esperado: {lap1.e_deploy_mj:.3f} MJ")
    assert 32.0 <= cut <= 36.0, f"corte fora do esperado: t = {cut} s"
    after_reset = _window(run.rows, 61.0, 62.0)
    assert all(r["mode_code"] == DEPLOYING for r in after_reset), (
        "deploy deveria voltar apos lap_reset")


@cocotb.test()
async def test_race_3_laps(dut):
    """Corrida de 3 voltas com o perfil padrao: regulamento respeitado."""
    run = CosimRun(dut, ErsPlant(), RaceScenario())
    await run.reset()
    await run.run(180.0)
    run._close_lap(3)
    path = run.save_csv("race_3_laps")

    dut._log.info("Resultados em %s", path)
    dut._log.info("Volta | Deploy (MJ) | Harvest (MJ) | VHDL (MJ) | SoC final")
    for lap in run.laps:
        dut._log.info("  %d   |   %6.3f    |    %6.3f    |  %6.3f   |  %5.1f%%",
                      lap.lap, lap.e_deploy_mj, lap.e_harvest_mj,
                      lap.e_vhdl_mj, lap.soc_end * 100)
    socs = [r["soc_pct"] for r in run.rows]
    p_max = max(r["p_deploy_kw"] for r in run.rows)
    dut._log.info("SoC min/max: %.1f%% / %.1f%%, deploy pico %.1f kW, modos: %s",
                  min(socs), max(socs), p_max,
                  sorted(MODE_NAMES[m] for m in run.modes_seen))
    dut._log.info("Trocas de modo: %d; maior excesso de potencia sobre o "
                  "setpoint: %.1f kW", run.mode_changes, run.max_excess_kw)

    assert FAULT not in run.modes_seen, "controlador entrou em FAULT"
    assert {DEPLOYING, HARVESTING_K, HARVESTING_H} <= run.modes_seen
    assert all(lap.e_deploy_mj <= 4.0 for lap in run.laps), "excedeu 4 MJ/volta"
    assert p_max <= 120.0, f"potencia de deploy acima de 120 kW: {p_max}"
    assert 20.0 <= min(socs) and max(socs) <= 95.0, "SoC fora de [20%, 95%]"
    # Histerese de SoC: sem oscilacao rapida entre deploy e harvest
    assert run.mode_changes <= 60, (
        f"FSM oscilando: {run.mode_changes} trocas de modo em 3 voltas")
    # Partida sem salto do PI: ao entrar em deploy a potencia nao pode saltar
    # acima do pedido. Sobra um overshoot transitorio de ~5% (atraso do
    # inversor + quantizacao do PWM); sem a pre-carga o salto era de ~43 kW.
    assert run.max_excess_kw <= 10.0, (
        f"pico de potencia {run.max_excess_kw:.1f} kW acima do setpoint")
