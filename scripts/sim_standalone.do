# ============================================================================
# Script  : sim_standalone.do
# Descricao: Roda simulacao standalone (sem Simulink) de todos os testbenches.
# Uso     : No ModelSim, execute: do ../scripts/sim_standalone.do
# Prerequisito: Executar compile_all.do primeiro.
# ============================================================================

echo "========================================"
echo "  SIMULACAO STANDALONE - ERS Project"
echo "========================================"

# ------------------------------------------------------------------
# Testbench 1: FSM isolada
# ------------------------------------------------------------------
echo ""
echo "--- Testbench: tb_ers_fsm ---"
vsim -t ns work.tb_ers_fsm
add wave -radix binary /tb_ers_fsm/clk
add wave -radix binary /tb_ers_fsm/rst_n
add wave -radix unsigned /tb_ers_fsm/brake_pres
add wave -radix unsigned /tb_ers_fsm/throttle
add wave -radix unsigned /tb_ers_fsm/soc_in
add wave -radix unsigned /tb_ers_fsm/turbo_rpm
add wave -radix unsigned /tb_ers_fsm/energy_used
add wave -radix binary /tb_ers_fsm/ers_mode
add wave -radix binary /tb_ers_fsm/harvest_k_en
add wave -radix binary /tb_ers_fsm/harvest_h_en
add wave -radix binary /tb_ers_fsm/deploy_en
add wave -radix binary /tb_ers_fsm/fault_active
run -all
echo "--- tb_ers_fsm concluido ---"
quit -sim

# ------------------------------------------------------------------
# Testbench 2: PI Controller isolado
# ------------------------------------------------------------------
echo ""
echo "--- Testbench: tb_pi_controller ---"
vsim -t ns work.tb_pi_controller
add wave -radix binary /tb_pi_controller/clk
add wave -radix binary /tb_pi_controller/rst_n
add wave -radix binary /tb_pi_controller/enable
add wave -radix unsigned /tb_pi_controller/setpoint
add wave -radix unsigned /tb_pi_controller/measured
add wave -radix unsigned /tb_pi_controller/duty_out
run -all
echo "--- tb_pi_controller concluido ---"
quit -sim

# ------------------------------------------------------------------
# Testbench 3: Power Arbiter isolado
# ------------------------------------------------------------------
echo ""
echo "--- Testbench: tb_power_arbiter ---"
vsim -t ns work.tb_power_arbiter
add wave -radix binary /tb_power_arbiter/clk
add wave -radix binary /tb_power_arbiter/rst_n
add wave -radix unsigned /tb_power_arbiter/duty_in
add wave -radix binary /tb_power_arbiter/deploy_en
add wave -radix binary /tb_power_arbiter/harvest_k_en
add wave -radix binary /tb_power_arbiter/harvest_h_en
add wave -radix unsigned /tb_power_arbiter/energy_used
add wave -radix binary /tb_power_arbiter/pwm_mguk
add wave -radix binary /tb_power_arbiter/pwm_mguh
add wave -radix unsigned /tb_power_arbiter/duty_limited
run -all
echo "--- tb_power_arbiter concluido ---"
quit -sim

# ------------------------------------------------------------------
# Testbench 4: Integracao (ers_top)
# ------------------------------------------------------------------
echo ""
echo "--- Testbench: tb_ers_top (integracao) ---"
vsim -t ns work.tb_ers_top
add wave -radix binary /tb_ers_top/clk
add wave -radix binary /tb_ers_top/rst_n
add wave -radix unsigned /tb_ers_top/speed_rpm
add wave -radix unsigned /tb_ers_top/brake_pres
add wave -radix unsigned /tb_ers_top/throttle
add wave -radix unsigned /tb_ers_top/soc_in
add wave -radix unsigned /tb_ers_top/turbo_rpm
add wave -radix binary /tb_ers_top/lap_reset
add wave -radix binary /tb_ers_top/pwm_mguk
add wave -radix binary /tb_ers_top/pwm_mguh
add wave -radix binary /tb_ers_top/ers_mode
add wave -radix unsigned /tb_ers_top/energy_used
add wave -radix binary /tb_ers_top/fault_flag
run -all
echo "--- tb_ers_top concluido ---"
quit -sim

echo ""
echo "========================================"
echo "  TODAS AS SIMULACOES CONCLUIDAS"
echo "========================================"
