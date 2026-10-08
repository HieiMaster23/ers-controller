#!/usr/bin/env python3
"""Gera graficos a partir dos CSVs da co-simulacao.

Uso:
    python cosim/plot_results.py                       # race_3_laps.csv
    python cosim/plot_results.py cosim/results/x.csv   # outro arquivo
    python cosim/plot_results.py --out docs/img/cosim_race.png

Requer matplotlib.
"""

import argparse
import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Patch  # noqa: E402

COSIM = Path(__file__).resolve().parent

# Paleta categorica validada (deploy, harvest K, harvest H) + tintas neutras
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_2 = "#52514e"
GRID = "#e4e3df"
STANDBY = "#d9d8d3"
FAULT = "#e34948"
DEPLOY = "#2a78d6"
HARV_K = "#eb6834"
HARV_H = "#1baf7a"

MODE_COLORS = {
    "STANDBY": STANDBY,
    "DEPLOYING": DEPLOY,
    "HARVESTING_K": HARV_K,
    "HARVESTING_H": HARV_H,
    "FAULT": FAULT,
}
MODE_LABELS = {
    "DEPLOYING": "Deploy (MGU-K traciona)",
    "HARVESTING_K": "Harvest MGU-K (frenagem)",
    "HARVESTING_H": "Harvest MGU-H (turbo)",
    "STANDBY": "Standby",
    "FAULT": "Fault",
}


def load(path: Path) -> dict:
    with path.open() as f:
        rows = list(csv.DictReader(f))
    cols = {k: [] for k in rows[0]}
    for r in rows:
        for k, v in r.items():
            try:
                cols[k].append(float(v))
            except ValueError:
                cols[k].append(v)
    return cols


def style_axis(ax, ylabel: str) -> None:
    ax.set_facecolor(SURFACE)
    ax.set_ylabel(ylabel, color=INK_2, fontsize=9)
    ax.tick_params(colors=INK_2, labelsize=8, length=0)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(GRID)


def label_end(ax, x, y, text, color) -> None:
    """Rotulo direto no fim da serie (texto em tinta neutra, marca colorida)."""
    ax.plot([x], [y], "o", color=color, markersize=5,
            markeredgecolor=SURFACE, markeredgewidth=1.5, clip_on=False)
    ax.annotate(text, (x, y), xytext=(6, 0), textcoords="offset points",
                va="center", fontsize=8, color=INK)


def mode_spans(t: list, modes: list):
    """Agrupa amostras consecutivas no mesmo modo em intervalos [t0, t1)."""
    dt = t[1] - t[0] if len(t) > 1 else 0.1
    start, cur = t[0] - dt, modes[0]
    for i in range(1, len(t)):
        if modes[i] != cur:
            yield start, t[i - 1], cur
            start, cur = t[i - 1], modes[i]
    yield start, t[-1], cur


def plot(cols: dict, out: Path, title: str) -> None:
    t = cols["t_s"]
    t_end = t[-1]
    lap_marks = [x for x in range(60, int(t_end) + 1, 60) if x < t_end]

    fig, axes = plt.subplots(
        5, 1, figsize=(11, 11.5), sharex=True,
        gridspec_kw={"height_ratios": [1.1, 0.35, 1.5, 1.2, 1.2], "hspace": 0.35})
    fig.patch.set_facecolor(SURFACE)
    fig.suptitle(title, x=0.06, ha="left", fontsize=13, color=INK, y=0.985)

    # 1. Piloto
    ax = axes[0]
    style_axis(ax, "Pedal (%)")
    ax.plot(t, cols["throttle_pct"], color=INK, linewidth=1.6)
    ax.plot(t, cols["brake_pct"], color=INK_2, linewidth=1.6, linestyle="--")
    label_end(ax, t_end, cols["throttle_pct"][-1], "Acelerador", INK)
    label_end(ax, t_end, cols["brake_pct"][-1], "Freio", INK_2)
    ax.set_ylim(0, 105)
    ax.set_title("O que o piloto faz", loc="left", fontsize=10, color=INK_2)

    # 2. Modo da FSM (VHDL)
    ax = axes[1]
    ax.set_facecolor(SURFACE)
    for t0, t1, mode in mode_spans(t, cols["mode"]):
        ax.axvspan(t0, t1, color=MODE_COLORS.get(mode, STANDBY), linewidth=0)
    ax.set_yticks([])
    for side in ax.spines.values():
        side.set_visible(False)
    ax.set_title("Decisao do controlador VHDL (ers_mode)", loc="left",
                 fontsize=10, color=INK_2)
    present = [m for m in MODE_LABELS if m in set(cols["mode"])]
    ax.legend(handles=[Patch(color=MODE_COLORS[m], label=MODE_LABELS[m])
                       for m in present],
              loc="upper center", bbox_to_anchor=(0.5, -0.25), ncol=len(present),
              frameon=False, fontsize=8, labelcolor=INK)

    # 3. Potencias
    ax = axes[2]
    style_axis(ax, "Potencia (kW)")
    # (coluna, cor, nome, deslocamento do rotulo de pico, alinhamento)
    series = [("p_deploy_kw", DEPLOY, "Deploy", (6, -3), "left", "top"),
              ("p_harv_k_kw", HARV_K, "Harvest K", (6, 3), "left", "bottom"),
              ("p_harv_h_kw", HARV_H, "Harvest H", (6, -3), "left", "top")]
    for key, color, *_ in series:
        ax.plot(t, cols[key], color=color, linewidth=1.6)
    ax.axhline(120, color=INK_2, linewidth=1, linestyle=":")
    ax.annotate("limite 120 kW", (0, 120), xytext=(2, 3),
                textcoords="offset points", fontsize=8, color=INK_2)
    for key, color, name, offset, ha, va in series:
        # Rotulo no pico de cada serie
        i = max(range(len(t)), key=lambda j: cols[key][j])
        ax.annotate(f"{name} ({cols[key][i]:.0f} kW)", (t[i], cols[key][i]),
                    xytext=offset, textcoords="offset points", fontsize=8,
                    ha=ha, va=va, color=INK)
        ax.plot([t[i]], [cols[key][i]], "o", color=color, markersize=5,
                markeredgecolor=SURFACE, markeredgewidth=1.5)
    ax.set_ylim(0, 135)
    ax.set_title("Fluxo de energia: tracao eletrica e recuperacao",
                 loc="left", fontsize=10, color=INK_2)

    # 4. SoC
    ax = axes[3]
    style_axis(ax, "SoC (%)")
    ax.axhspan(0, 20, color=GRID, linewidth=0)
    ax.axhspan(95, 100, color=GRID, linewidth=0)
    ax.plot(t, cols["soc_pct"], color=INK, linewidth=1.8)
    for level, text, dy, va in [
            (25, "deploy para em 25% e so volta com 30%", -3, "top"),
            (90, "harvest para em 90% e so volta com 85%", 3, "bottom")]:
        ax.axhline(level, color=INK_2, linewidth=1, linestyle=":")
        ax.annotate(text, (t_end, level), xytext=(-4, dy), ha="right", va=va,
                    textcoords="offset points", fontsize=8, color=INK_2)
    ax.annotate("FAULT", (0, 10), xytext=(2, 0), textcoords="offset points",
                va="center", fontsize=8, color=INK_2)
    ax.set_ylim(0, 100)
    ax.set_title("Carga da bateria", loc="left", fontsize=10, color=INK_2)

    # 5. Energia por volta
    ax = axes[4]
    style_axis(ax, "Energia na volta (MJ)")
    ax.plot(t, cols["e_vhdl_mj"], color=DEPLOY, linewidth=1.8)
    ax.plot(t, cols["e_lap_deploy_mj"], color=INK_2, linewidth=1.4,
            linestyle="--")
    ax.axhline(4.0, color=INK_2, linewidth=1, linestyle=":")
    ax.annotate("limite 4 MJ/volta", (0, 4.0), xytext=(2, 3),
                textcoords="offset points", fontsize=8, color=INK_2)
    label_end(ax, t_end, cols["e_vhdl_mj"][-1], "Medido pelo VHDL", DEPLOY)
    label_end(ax, t_end, cols["e_lap_deploy_mj"][-1] - 0.25,
              "Entregue (planta)", INK_2)
    ax.set_ylim(0, 4.6)
    ax.set_xlabel("Tempo (s)", color=INK_2, fontsize=9)
    ax.set_title("Energia de deploy acumulada (zera a cada volta)",
                 loc="left", fontsize=10, color=INK_2)

    for ax in axes:
        for x in lap_marks:
            ax.axvline(x, color=INK_2, linewidth=0.8, alpha=0.5)
        ax.set_xlim(0, t_end)
    for x in lap_marks:
        axes[0].annotate(f"volta {x // 60 + 1}", (x, 105), xytext=(3, -10),
                         textcoords="offset points", fontsize=8, color=INK_2)

    fig.subplots_adjust(left=0.07, right=0.86, top=0.94, bottom=0.05)
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=130, facecolor=SURFACE)
    print(f"Grafico salvo em {out}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("csv", nargs="?", default=COSIM / "results" / "race_3_laps.csv",
                    type=Path)
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--title", default="Co-simulacao ERS: VHDL real + planta Python")
    args = ap.parse_args()
    out = args.out or args.csv.with_suffix(".png")
    plot(load(args.csv), out, args.title)


if __name__ == "__main__":
    main()
