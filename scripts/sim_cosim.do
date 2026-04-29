# ============================================================================
# Script  : sim_cosim.do
# Descricao: Inicializa co-simulacao com Simulink via HDL Verifier.
#            Compila o projeto e aguarda conexao TCP do Simulink.
# Uso     : No ModelSim, execute: do ../scripts/sim_cosim.do
#            Em seguida, inicie a simulacao no Simulink (cosim_top.slx).
# ============================================================================

echo "========================================"
echo "  CO-SIMULACAO ERS - ModelSim + Simulink"
echo "========================================"

# Compilar tudo primeiro
do ../scripts/compile_all.do

# Carregar o design top-level para co-simulacao
echo ""
echo "Carregando ers_top para co-simulacao..."
vsim -t ns work.ers_top

# Adicionar ondas para monitoramento
add wave -radix binary /ers_top/clk
add wave -radix binary /ers_top/rst_n
add wave -radix unsigned /ers_top/speed_rpm
add wave -radix unsigned /ers_top/brake_pres
add wave -radix unsigned /ers_top/throttle
add wave -radix unsigned /ers_top/soc_in
add wave -radix unsigned /ers_top/turbo_rpm
add wave -radix binary /ers_top/lap_reset
add wave -radix binary /ers_top/pwm_mguk
add wave -radix binary /ers_top/pwm_mguh
add wave -radix binary /ers_top/ers_mode
add wave -radix unsigned /ers_top/energy_used
add wave -radix binary /ers_top/fault_flag

# Sinais internos para debug
add wave -radix binary /ers_top/u_fsm/state_reg
add wave -radix unsigned /ers_top/u_pi/duty_out
add wave -radix unsigned /ers_top/u_arbiter/duty_limited
add wave -radix unsigned /ers_top/u_energy/energy_accum

echo ""
echo "========================================"
echo "  ModelSim pronto para co-simulacao."
echo "  Inicie a simulacao no Simulink."
echo "  Porta TCP: 4449 (padrao HDL Verifier)"
echo "========================================"

# A simulacao sera controlada pelo Simulink via HDL Verifier
# O comando 'run' nao e necessario aqui - o Simulink controla o avanco
