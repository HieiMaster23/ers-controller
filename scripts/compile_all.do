# ============================================================================
# Script  : compile_all.do
# Descricao: Compila todos os arquivos VHDL do projeto ERS no ModelSim.
# Uso     : No ModelSim, execute: do ../scripts/compile_all.do
# ============================================================================

# Criar/limpar biblioteca de trabalho
vlib work
vmap work work

# Compilar modulos VHDL (ordem de dependencia)
echo "Compilando ers_fsm.vhd..."
vcom -93 -work work ../vhdl/ers_fsm.vhd

echo "Compilando pi_controller.vhd..."
vcom -93 -work work ../vhdl/pi_controller.vhd

echo "Compilando power_arbiter.vhd..."
vcom -93 -work work ../vhdl/power_arbiter.vhd

echo "Compilando energy_meter.vhd..."
vcom -93 -work work ../vhdl/energy_meter.vhd

echo "Compilando ers_top.vhd..."
vcom -93 -work work ../vhdl/ers_top.vhd

# Compilar testbenches
echo "Compilando tb_ers_fsm.vhd..."
vcom -93 -work work ../testbench/tb_ers_fsm.vhd

echo "Compilando tb_pi_controller.vhd..."
vcom -93 -work work ../testbench/tb_pi_controller.vhd

echo "Compilando tb_power_arbiter.vhd..."
vcom -93 -work work ../testbench/tb_power_arbiter.vhd

echo "Compilando tb_ers_top.vhd..."
vcom -93 -work work ../testbench/tb_ers_top.vhd

echo "========================================"
echo "  Compilacao concluida com sucesso."
echo "========================================"
