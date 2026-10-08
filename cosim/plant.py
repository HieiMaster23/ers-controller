"""Planta fisica do ERS para co-simulacao com o controlador VHDL.

Reproduz o modelo de simulink/create_vehicle_model.m (mesmos parametros e
mesmo perfil de volta), em Python puro, sem dependencias externas. Pode ser
usada sozinha (testes rapidos) ou acoplada ao VHDL via cocotb
(cosim/test_ers_cosim.py).

Diferencas em relacao ao modelo Simulink:
  - Harvest so acontece quando o controlador comanda (modo + PWM ativo).
    No Simulink a planta recuperava energia sempre, independente da FSM.
  - O deploy segue o duty do PWM do MGU-K, com dinamica de 1a ordem do
    inversor (TAU) e queda de tensao da bateria (R interna): o PI do VHDL
    precisa compensar essa queda para entregar a potencia pedida.
  - A potencia de deploy medida volta ao VHDL (p_mguk_meas), fechando a
    malha do PI.
"""

from __future__ import annotations

import bisect
import math
from dataclasses import dataclass

# Codigos de ers_mode (ver vhdl/ers_fsm.vhd)
STANDBY = 0b000
HARVESTING_K = 0b001
HARVESTING_H = 0b010
DEPLOYING = 0b011
FAULT = 0b111

MODE_NAMES = {
    STANDBY: "STANDBY",
    HARVESTING_K: "HARVESTING_K",
    HARVESTING_H: "HARVESTING_H",
    DEPLOYING: "DEPLOYING",
    FAULT: "FAULT",
}


@dataclass
class PlantParams:
    """Parametros fisicos (mesmos valores de create_vehicle_model.m)."""

    v_nom: float = 400.0          # V, tensao nominal do barramento HV
    e_bat: float = 4e6            # J, capacidade da bateria
    soc0: float = 0.70            # SoC inicial
    r_int: float = 0.05           # Ohm, resistencia interna
    k_mguk_torque: float = 0.8    # Nm/bar de pressao de freio
    p_max_mguk: float = 120e3     # W, potencia maxima do MGU-K
    eta_mguk: float = 0.90        # rendimento do MGU-K em harvest
    k_turbo: float = 1.5e-5       # W/RPM^2
    p_max_mguh: float = 50e3      # W, potencia maxima do MGU-H
    tau_mguk: float = 0.020       # s, constante de tempo do inversor do MGU-K


@dataclass
class DriverInputs:
    """Sinais do carro/piloto em um instante, ja na escala dos ADCs."""

    speed_rpm: int
    brake_adc: int     # 0-4095 = 0-100 bar
    throttle_adc: int  # 0-4095 = 0-100%
    turbo_rpm: int


def _interp(x: float, xs: list[float], ys: list[float]) -> float:
    """Interpolacao linear (equivalente ao 1-D Lookup Table do Simulink)."""
    if x <= xs[0]:
        return ys[0]
    if x >= xs[-1]:
        return ys[-1]
    i = bisect.bisect_right(xs, x)
    x0, x1, y0, y1 = xs[i - 1], xs[i], ys[i - 1], ys[i]
    return y0 + (y1 - y0) * (x - x0) / (x1 - x0)


class RaceScenario:
    """Volta de 60 s: aceleracao, frenagem, curva e saida de curva."""

    SPEED = ([0, 10, 20, 28, 32, 35, 38, 45, 55, 60],
             [3000, 15000, 18000, 18000, 8000, 5000, 5000, 8000, 15000, 3000])
    BRAKE = ([0, 10, 20, 28, 30, 33, 36, 40, 50, 60],
             [0, 0, 0, 0, 3500, 4095, 2000, 0, 0, 0])
    THROTTLE = ([0, 10, 20, 28, 30, 35, 38, 45, 55, 60],
                [2048, 3500, 4095, 4095, 0, 0, 500, 2500, 4095, 2048])
    TURBO = ([0, 10, 20, 28, 32, 36, 40, 45, 55, 60],
             [20000, 45000, 60000, 65000, 30000, 20000, 25000, 40000, 60000, 20000])

    lap_time = 60.0

    def at(self, t: float) -> DriverInputs:
        t_lap = math.fmod(t, self.lap_time)
        return DriverInputs(
            speed_rpm=round(_interp(t_lap, *self.SPEED)),
            brake_adc=round(_interp(t_lap, *self.BRAKE)),
            throttle_adc=round(_interp(t_lap, *self.THROTTLE)),
            turbo_rpm=round(_interp(t_lap, *self.TURBO)),
        )


class ConstantScenario:
    """Entradas constantes (para testes isolados)."""

    def __init__(self, inputs: DriverInputs, lap_time: float = 60.0):
        self.inputs = inputs
        self.lap_time = lap_time

    def at(self, t: float) -> DriverInputs:
        return self.inputs


class ErsPlant:
    """Bateria + MGU-K + MGU-H, integrados com passo fixo."""

    def __init__(self, params: PlantParams | None = None):
        self.p = params or PlantParams()
        self.soc = self.p.soc0
        self.v_term = self.p.v_nom
        self.p_deploy = 0.0      # W eletricos entregues ao MGU-K (tracao)
        self.p_harv_k = 0.0      # W recuperados pelo MGU-K
        self.p_harv_h = 0.0      # W recuperados pelo MGU-H
        self.e_lap_deploy = 0.0  # J de deploy na volta atual
        self.e_lap_harvest = 0.0 # J recuperados na volta atual

    # ------------------------------------------------------------------
    # Potencia disponivel (o que a fisica permite recuperar)
    # ------------------------------------------------------------------
    def available_harvest_k(self, inp: DriverInputs) -> float:
        brake_bar = inp.brake_adc * 100.0 / 4095.0
        omega = inp.speed_rpm * 2.0 * math.pi / 60.0
        p_elec = self.p.k_mguk_torque * brake_bar * omega * self.p.eta_mguk
        return min(p_elec, self.p.p_max_mguk)

    def available_harvest_h(self, inp: DriverInputs) -> float:
        return min(self.p.k_turbo * inp.turbo_rpm ** 2, self.p.p_max_mguh)

    # ------------------------------------------------------------------
    # Interface com o controlador
    # ------------------------------------------------------------------
    @property
    def soc_adc(self) -> int:
        return max(0, min(4095, round(self.soc * 4095)))

    @property
    def p_meas_adc(self) -> int:
        """Potencia de deploy medida: 0-65535 = 0-P_MAX do MGU-K."""
        frac = self.p_deploy / self.p.p_max_mguk
        return max(0, min(65535, round(frac * 65535)))

    def new_lap(self) -> None:
        self.e_lap_deploy = 0.0
        self.e_lap_harvest = 0.0

    def step(self, dt: float, inp: DriverInputs, mode: int,
             duty_k: float, duty_h: float) -> None:
        """Avanca dt segundos dado o comando do controlador.

        duty_k / duty_h: fracao 0-1 do PWM medido no ultimo periodo.
        """
        p = self.p

        # Deploy: potencia comandada pelo duty, limitada pela tensao atual
        # da bateria (sob carga a tensao cai e a potencia disponivel tambem).
        if mode == DEPLOYING:
            p_cmd = duty_k * p.p_max_mguk * (self.v_term / p.v_nom)
        else:
            p_cmd = 0.0
        alpha = 1.0 - math.exp(-dt / p.tau_mguk)  # 1a ordem discretizada
        self.p_deploy += (p_cmd - self.p_deploy) * alpha

        # Harvest: so quando o controlador habilita (modo + PWM ativo)
        harvest_k_on = mode == HARVESTING_K and duty_k > 0.0
        harvest_h_on = mode == HARVESTING_H and duty_h > 0.0
        self.p_harv_k = self.available_harvest_k(inp) if harvest_k_on else 0.0
        self.p_harv_h = self.available_harvest_h(inp) if harvest_h_on else 0.0

        # Bateria: P > 0 carrega
        p_bat = self.p_harv_k + self.p_harv_h - self.p_deploy
        i_bat = p_bat / p.v_nom
        self.v_term = p.v_nom + p.r_int * i_bat
        self.soc = min(1.0, max(0.0, self.soc + p_bat * dt / p.e_bat))

        self.e_lap_deploy += self.p_deploy * dt
        self.e_lap_harvest += (self.p_harv_k + self.p_harv_h) * dt
