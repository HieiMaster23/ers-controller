#!/usr/bin/env bash
# ============================================================================
# Script  : run_tests.sh
# Descricao: Compila o projeto e roda todos os testbenches com GHDL
#            (simulador VHDL livre). Retorna codigo != 0 se algum falhar.
# Uso     : ./scripts/run_tests.sh            (todos os testbenches)
#           ./scripts/run_tests.sh tb_ers_fsm (apenas os indicados)
# ============================================================================
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/ghdl"
GHDL_FLAGS=(--std=08 --workdir="$BUILD")
# Qualquer assert de severidade error encerra a simulacao com falha.
RUN_FLAGS=(--assert-level=error --ieee-asserts=disable-at-0 --stop-time=1sec)

SOURCES=(
    vhdl/ers_fsm.vhd
    vhdl/pi_controller.vhd
    vhdl/power_arbiter.vhd
    vhdl/energy_meter.vhd
    vhdl/ers_top.vhd
    testbench/tb_ers_fsm.vhd
    testbench/tb_pi_controller.vhd
    testbench/tb_power_arbiter.vhd
    testbench/tb_energy_meter.vhd
    testbench/tb_ers_top.vhd
)

if [ $# -gt 0 ]; then
    TESTBENCHES=("$@")
else
    TESTBENCHES=(tb_ers_fsm tb_pi_controller tb_power_arbiter tb_energy_meter tb_ers_top)
fi

command -v ghdl >/dev/null || { echo "ERRO: ghdl nao encontrado no PATH"; exit 2; }

mkdir -p "$BUILD"
rm -f "$BUILD"/*.cf
cd "$ROOT"

echo "== Compilando"
for src in "${SOURCES[@]}"; do
    ghdl -a "${GHDL_FLAGS[@]}" "$src" || { echo "ERRO: falha ao compilar $src"; exit 1; }
done

failed=()
for tb in "${TESTBENCHES[@]}"; do
    echo "== $tb"
    log="$BUILD/$tb.log"
    ghdl -r "${GHDL_FLAGS[@]}" "$tb" "${RUN_FLAGS[@]}" >"$log" 2>&1
    status=$?
    grep -E "FALHA|report note" "$log" | sed 's/^.*(report note): /   /; s/^.*(assertion error): /   /'
    # Testbench que nao termina sozinho (clock nao para) tambem e falha
    if grep -q "simulation stopped by --stop-time" "$log"; then
        echo "   testbench nao terminou (sim_done nunca ativado)"
        status=1
    fi
    if [ $status -eq 0 ]; then
        echo "   PASSOU"
    else
        echo "   FALHOU (log completo: $log)"
        failed+=("$tb")
    fi
done

echo
if [ ${#failed[@]} -eq 0 ]; then
    echo "Resultado: ${#TESTBENCHES[@]}/${#TESTBENCHES[@]} testbenches passaram"
else
    echo "Resultado: ${#failed[@]} de ${#TESTBENCHES[@]} falharam: ${failed[*]}"
    exit 1
fi
