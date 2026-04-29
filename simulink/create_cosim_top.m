%% create_cosim_top.m
% Cria o modelo Simulink cosim_top.slx para co-simulacao com ModelSim.
% Este modelo referencia vehicle_model como subsistema e adiciona o bloco
% HDL Cosimulation para conectar com ers_top.vhd no ModelSim.
%
% PRE-REQUISITOS:
%   1. Executar create_vehicle_model.m antes (gera vehicle_model.slx)
%   2. HDL Verifier toolbox instalado
%   3. ModelSim rodando com ers_top carregado (do sim_cosim.do)
%
% Autor: Rafael
% Data: 2026-04-06
% Projeto: ERS Simulation Project

%% Limpar ambiente
close all; clc;

modelName = 'cosim_top';

% Fecha modelo se ja estiver aberto
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
if exist([modelName '.slx'], 'file')
    delete([modelName '.slx']);
end

%% =========================================================
%  PARAMETROS (mesmos do vehicle_model)
%  =========================================================
V_bus_nominal  = 400;
Q_max_battery  = 4e6;
SoC_inicial    = 0.70;
R_internal     = 0.05;
K_mguk_torque  = 0.8;
P_max_mguk     = 120e3;
eta_mguk       = 0.90;
k_turbo        = 1.5e-5;
P_max_mguh     = 50e3;
Ts             = 1e-3;
T_volta        = 60;
T_sim          = 180;

% Parametros da co-simulacao
VHDL_CLK_PERIOD = 20e-9;  % 50 MHz -> 20 ns

% Salvar no workspace
vars = {'V_bus_nominal','Q_max_battery','SoC_inicial','R_internal', ...
        'K_mguk_torque','P_max_mguk','eta_mguk','k_turbo','P_max_mguh', ...
        'Ts','T_volta','T_sim','VHDL_CLK_PERIOD'};
for i = 1:length(vars)
    assignin('base', vars{i}, eval(vars{i}));
end

%% =========================================================
%  CRIAR MODELO
%  =========================================================
new_system(modelName);
open_system(modelName);

set_param(modelName, 'Solver', 'ode4');
set_param(modelName, 'FixedStep', num2str(Ts));
set_param(modelName, 'StopTime', num2str(T_sim));

%% =========================================================
%  SUBSISTEMA: PLANTA FISICA (referencia ao vehicle_model)
%  =========================================================
% Adicionar vehicle_model como Model Reference ou copia como subsistema
% Usamos blocos equivalentes inline para evitar dependencia de .slx

plant_path = [modelName '/Plant'];
add_block('simulink/Ports & Subsystems/Subsystem', plant_path);
delete_line(plant_path, 'In1/1', 'Out1/1');
delete_block([plant_path '/In1']);
delete_block([plant_path '/Out1']);

% ---- Cenario de corrida (mesmo do vehicle_model) ----
add_block('simulink/Sources/Clock', [plant_path '/Clock']);
add_block('simulink/Math Operations/Math Function', [plant_path '/Mod']);
set_param([plant_path '/Mod'], 'Operator', 'mod');
add_block('simulink/Sources/Constant', [plant_path '/T_volta']);
set_param([plant_path '/T_volta'], 'Value', 'T_volta');
add_line(plant_path, 'Clock/1', 'Mod/1');
add_line(plant_path, 'T_volta/1', 'Mod/2');

% Perfil de velocidade
add_block('simulink/Lookup Tables/1-D Lookup Table', [plant_path '/Speed_LUT']);
set_param([plant_path '/Speed_LUT'], ...
    'Table', '[3000,15000,18000,18000,8000,5000,5000,8000,15000,3000]', ...
    'BreakpointsForDimension1', '[0,10,20,28,32,35,38,45,55,60]');
add_line(plant_path, 'Mod/1', 'Speed_LUT/1');

% Perfil de frenagem
add_block('simulink/Lookup Tables/1-D Lookup Table', [plant_path '/Brake_LUT']);
set_param([plant_path '/Brake_LUT'], ...
    'Table', '[0,0,0,0,3500,4095,2000,0,0,0]', ...
    'BreakpointsForDimension1', '[0,10,20,28,30,33,36,40,50,60]');
add_line(plant_path, 'Mod/1', 'Brake_LUT/1');

% Perfil de acelerador
add_block('simulink/Lookup Tables/1-D Lookup Table', [plant_path '/Throttle_LUT']);
set_param([plant_path '/Throttle_LUT'], ...
    'Table', '[2048,3500,4095,4095,0,0,500,2500,4095,2048]', ...
    'BreakpointsForDimension1', '[0,10,20,28,30,35,38,45,55,60]');
add_line(plant_path, 'Mod/1', 'Throttle_LUT/1');

% Perfil do turbo
add_block('simulink/Lookup Tables/1-D Lookup Table', [plant_path '/Turbo_LUT']);
set_param([plant_path '/Turbo_LUT'], ...
    'Table', '[20000,45000,60000,65000,30000,20000,25000,40000,60000,20000]', ...
    'BreakpointsForDimension1', '[0,10,20,28,32,36,40,45,55,60]');
add_line(plant_path, 'Mod/1', 'Turbo_LUT/1');

% ---- MGU-K (mesmo modelo simplificado) ----
add_block('simulink/Math Operations/Gain', [plant_path '/ADC_to_bar']);
set_param([plant_path '/ADC_to_bar'], 'Gain', '100/4095');
add_block('simulink/Math Operations/Gain', [plant_path '/RPM_to_rads']);
set_param([plant_path '/RPM_to_rads'], 'Gain', '2*pi/60');
add_block('simulink/Math Operations/Gain', [plant_path '/K_torque']);
set_param([plant_path '/K_torque'], 'Gain', 'K_mguk_torque');
add_block('simulink/Math Operations/Product', [plant_path '/P_mech']);
add_block('simulink/Math Operations/Gain', [plant_path '/Eta']);
set_param([plant_path '/Eta'], 'Gain', 'eta_mguk');
add_block('simulink/Discontinuities/Saturation', [plant_path '/Sat_K']);
set_param([plant_path '/Sat_K'], 'UpperLimit', 'P_max_mguk', 'LowerLimit', '0');

add_line(plant_path, 'Brake_LUT/1',  'ADC_to_bar/1');
add_line(plant_path, 'Speed_LUT/1',  'RPM_to_rads/1');
add_line(plant_path, 'ADC_to_bar/1', 'K_torque/1');
add_line(plant_path, 'K_torque/1',   'P_mech/1');
add_line(plant_path, 'RPM_to_rads/1','P_mech/2');
add_line(plant_path, 'P_mech/1',     'Eta/1');
add_line(plant_path, 'Eta/1',        'Sat_K/1');

% ---- MGU-H ----
add_block('simulink/Math Operations/Math Function', [plant_path '/Square']);
set_param([plant_path '/Square'], 'Operator', 'square');
add_block('simulink/Math Operations/Gain', [plant_path '/K_turbo_gain']);
set_param([plant_path '/K_turbo_gain'], 'Gain', 'k_turbo');
add_block('simulink/Discontinuities/Saturation', [plant_path '/Sat_H']);
set_param([plant_path '/Sat_H'], 'UpperLimit', 'P_max_mguh', 'LowerLimit', '0');

add_line(plant_path, 'Turbo_LUT/1', 'Square/1');
add_line(plant_path, 'Square/1',    'K_turbo_gain/1');
add_line(plant_path, 'K_turbo_gain/1', 'Sat_H/1');

% ---- Bateria HV ----
% Entrada extra: P_deploy vinda do controlador (realimentacao de descarga)
add_block('simulink/Ports & Subsystems/In1', [plant_path '/P_deploy_in']);

% Sum_P com 3 entradas: +P_mguk +P_mguh -P_deploy
add_block('simulink/Math Operations/Add', [plant_path '/Sum_P']);
set_param([plant_path '/Sum_P'], 'Inputs', '++-');

add_block('simulink/Math Operations/Gain', [plant_path '/P_to_I']);
set_param([plant_path '/P_to_I'], 'Gain', '1/V_bus_nominal');
add_block('simulink/Math Operations/Gain', [plant_path '/I_to_dSoC']);
set_param([plant_path '/I_to_dSoC'], 'Gain', '1/(Q_max_battery/V_bus_nominal)');
add_block('simulink/Continuous/Integrator', [plant_path '/SoC_Int']);
set_param([plant_path '/SoC_Int'], ...
    'InitialCondition', 'SoC_inicial', ...
    'LimitOutput', 'on', ...
    'UpperSaturationLimit', '0.95', ...
    'LowerSaturationLimit', '0.20');
add_block('simulink/Math Operations/Gain', [plant_path '/SoC_to_ADC']);
set_param([plant_path '/SoC_to_ADC'], 'Gain', '4095');

add_line(plant_path, 'Sat_K/1',       'Sum_P/1');   % +P_harvest_K
add_line(plant_path, 'Sat_H/1',       'Sum_P/2');   % +P_harvest_H
add_line(plant_path, 'P_deploy_in/1', 'Sum_P/3');   % -P_deploy
add_line(plant_path, 'Sum_P/1',       'P_to_I/1');
add_line(plant_path, 'P_to_I/1',      'I_to_dSoC/1');
add_line(plant_path, 'I_to_dSoC/1',   'SoC_Int/1');
add_line(plant_path, 'SoC_Int/1',     'SoC_to_ADC/1');

% ---- Lap Reset: pulso de 1 amostra a cada T_volta ----
% Usa Sample based para evitar problemas de precisao floating-point
% com o passo fixo. Period = T_volta/Ts samples, pulse = 1 sample.
add_block('simulink/Sources/Pulse Generator', [plant_path '/Lap_Pulse']);
set_param([plant_path '/Lap_Pulse'], ...
    'PulseType',   'Sample based', ...
    'Period',      'T_volta/Ts', ...    % numero de amostras por volta
    'PulseWidth',  '1', ...              % 1 amostra = Ts de duracao
    'PhaseDelay',  '0', ...
    'Amplitude',   '1', ...
    'SampleTime',  'Ts');

% ---- Saidas da planta ----
add_block('simulink/Ports & Subsystems/Out1', [plant_path '/speed_rpm']);
add_block('simulink/Ports & Subsystems/Out1', [plant_path '/brake_pres']);
add_block('simulink/Ports & Subsystems/Out1', [plant_path '/throttle']);
add_block('simulink/Ports & Subsystems/Out1', [plant_path '/soc_adc']);
add_block('simulink/Ports & Subsystems/Out1', [plant_path '/turbo_rpm']);
add_block('simulink/Ports & Subsystems/Out1', [plant_path '/soc_percent']);
add_block('simulink/Ports & Subsystems/Out1', [plant_path '/P_mguk']);
add_block('simulink/Ports & Subsystems/Out1', [plant_path '/P_mguh']);
add_block('simulink/Ports & Subsystems/Out1', [plant_path '/lap_reset']);

add_line(plant_path, 'Speed_LUT/1',    'speed_rpm/1');
add_line(plant_path, 'Brake_LUT/1',    'brake_pres/1');
add_line(plant_path, 'Throttle_LUT/1', 'throttle/1');
add_line(plant_path, 'SoC_to_ADC/1',   'soc_adc/1');
add_line(plant_path, 'Turbo_LUT/1',    'turbo_rpm/1');
add_line(plant_path, 'SoC_Int/1',      'soc_percent/1');
add_line(plant_path, 'Sat_K/1',        'P_mguk/1');
add_line(plant_path, 'Sat_H/1',        'P_mguh/1');
add_line(plant_path, 'Lap_Pulse/1',    'lap_reset/1');

%% =========================================================
%  BLOCO HDL COSIMULATION (ou substituto para teste)
%  =========================================================
% Nota: O bloco 'HDL Cosimulation' requer HDL Verifier toolbox.
% Se nao estiver disponivel, criamos um subsistema placeholder que
% simula o comportamento basico do controlador VHDL para teste.

hasHDLVerifier = license('test', 'HDL_Verifier');

if hasHDLVerifier
    % ---- Bloco HDL Cosimulation real ----
    fprintf('HDL Verifier detectado. Criando bloco de co-simulacao real.\n');

    hdl_path = [modelName '/HDL_Cosim'];
    add_block('hdlverifier/HDL Cosimulation/HDL Cosimulation', hdl_path);

    % Configurar conexao com ModelSim
    set_param(hdl_path, ...
        'CommShared', 'off', ...
        'CommPortNumber', '4449');

    % Nota: O mapeamento de sinais deve ser feito manualmente no bloco
    % apos abrir o modelo, pois depende da sessao ativa do ModelSim.
    % Instrucoes detalhadas em docs/04_cosimulacao.md

    fprintf('IMPORTANTE: Abra o bloco HDL Cosim e configure os sinais manualmente.\n');
    fprintf('Veja docs/04_cosimulacao.md para instrucoes detalhadas.\n');

else
    % ---- Placeholder: controlador simplificado em Simulink ----
    fprintf('HDL Verifier NAO detectado.\n');
    fprintf('Criando controlador placeholder em Simulink para teste.\n');
    fprintf('Para co-simulacao real, instale HDL Verifier e recrie.\n');

    hdl_path = [modelName '/VHDL_Controller'];
    add_block('simulink/Ports & Subsystems/Subsystem', hdl_path);
    delete_line(hdl_path, 'In1/1', 'Out1/1');
    delete_block([hdl_path '/In1']);
    delete_block([hdl_path '/Out1']);

    % Entradas (mesmas do ers_top.vhd)
    add_block('simulink/Ports & Subsystems/In1', [hdl_path '/speed_rpm']);
    add_block('simulink/Ports & Subsystems/In1', [hdl_path '/brake_pres']);
    add_block('simulink/Ports & Subsystems/In1', [hdl_path '/throttle']);
    add_block('simulink/Ports & Subsystems/In1', [hdl_path '/soc_adc']);
    add_block('simulink/Ports & Subsystems/In1', [hdl_path '/turbo_rpm']);
    add_block('simulink/Ports & Subsystems/In1', [hdl_path '/lap_reset']);

    % Logica simplificada da FSM (replica da VHDL ers_fsm):
    %   Deploy quando throttle > 2048 e SoC > 25% (1024) e E_volta < 4MJ
    %   Potencia de deploy proporcional ao throttle (ate P_max_mguk)

    % Comparadores para deploy
    add_block('simulink/Logic and Bit Operations/Compare To Constant', ...
        [hdl_path '/Throttle_GT']);
    set_param([hdl_path '/Throttle_GT'], 'relop', '>', 'const', '2048');

    add_block('simulink/Logic and Bit Operations/Compare To Constant', ...
        [hdl_path '/SoC_GT_Deploy']);
    set_param([hdl_path '/SoC_GT_Deploy'], 'relop', '>', 'const', '1024');

    add_line(hdl_path, 'throttle/1', 'Throttle_GT/1');
    add_line(hdl_path, 'soc_adc/1',  'SoC_GT_Deploy/1');

    % Escala do throttle para duty (0-65520) e depois para potencia (W)
    add_block('simulink/Math Operations/Gain', [hdl_path '/Throttle_Scale']);
    set_param([hdl_path '/Throttle_Scale'], 'Gain', '16');
    add_line(hdl_path, 'throttle/1', 'Throttle_Scale/1');

    % Conversao duty -> potencia: P_W = duty/65535 * P_max_mguk
    add_block('simulink/Math Operations/Gain', [hdl_path '/Duty_to_P']);
    set_param([hdl_path '/Duty_to_P'], 'Gain', 'P_max_mguk/65535');
    add_line(hdl_path, 'Throttle_Scale/1', 'Duty_to_P/1');

    % --- Acumulador de energia por volta (reseta em lap_reset) ---
    add_block('simulink/Continuous/Integrator', [hdl_path '/E_Lap']);
    set_param([hdl_path '/E_Lap'], ...
        'InitialCondition', '0', ...
        'ExternalReset',    'rising');

    % Comparador E_volta < 4 MJ
    add_block('simulink/Logic and Bit Operations/Compare To Constant', ...
        [hdl_path '/E_LT_Max']);
    set_param([hdl_path '/E_LT_Max'], 'relop', '<', 'const', '4e6');
    add_line(hdl_path, 'E_Lap/1', 'E_LT_Max/1');

    % AND de 3 entradas: throttle>2048 AND soc>1024 AND E<4MJ
    add_block('simulink/Logic and Bit Operations/Logical Operator', ...
        [hdl_path '/AND_Deploy']);
    set_param([hdl_path '/AND_Deploy'], 'Inputs', '3');
    add_line(hdl_path, 'Throttle_GT/1',   'AND_Deploy/1');
    add_line(hdl_path, 'SoC_GT_Deploy/1', 'AND_Deploy/2');
    add_line(hdl_path, 'E_LT_Max/1',      'AND_Deploy/3');

    % Switch de deploy: se deploy ativo -> P_deploy, senao 0
    add_block('simulink/Signal Routing/Switch', [hdl_path '/Deploy_Switch']);
    set_param([hdl_path '/Deploy_Switch'], 'Criteria', 'u2 ~= 0');
    add_block('simulink/Sources/Constant', [hdl_path '/Zero']);
    set_param([hdl_path '/Zero'], 'Value', '0');

    add_line(hdl_path, 'Duty_to_P/1',  'Deploy_Switch/1');
    add_line(hdl_path, 'AND_Deploy/1', 'Deploy_Switch/2');
    add_line(hdl_path, 'Zero/1',       'Deploy_Switch/3');

    % Fecha o loop: potencia efetiva integrada -> E_Lap (reset = lap_reset)
    add_line(hdl_path, 'Deploy_Switch/1', 'E_Lap/1');
    add_line(hdl_path, 'lap_reset/1',     'E_Lap/2');

    % --- Saidas ---
    add_block('simulink/Ports & Subsystems/Out1', [hdl_path '/pwm_duty']);
    add_block('simulink/Ports & Subsystems/Out1', [hdl_path '/ers_mode']);
    add_block('simulink/Ports & Subsystems/Out1', [hdl_path '/energy_lap']);
    add_block('simulink/Ports & Subsystems/Out1', [hdl_path '/P_deploy']);

    % Duty reconstituido a partir da potencia efetiva (com corte por E>4MJ)
    add_block('simulink/Math Operations/Gain', [hdl_path '/P_to_Duty']);
    set_param([hdl_path '/P_to_Duty'], 'Gain', '65535/P_max_mguk');
    add_line(hdl_path, 'Deploy_Switch/1', 'P_to_Duty/1');
    add_line(hdl_path, 'P_to_Duty/1',     'pwm_duty/1');

    % ers_mode: 3 = deploy ativo, 0 = standby (simplificado)
    add_block('simulink/Math Operations/Gain', [hdl_path '/Mode_Scale']);
    set_param([hdl_path '/Mode_Scale'], 'Gain', '3');
    add_line(hdl_path, 'AND_Deploy/1', 'Mode_Scale/1');
    add_line(hdl_path, 'Mode_Scale/1', 'ers_mode/1');

    % Energia por volta (saida para monitoramento)
    add_line(hdl_path, 'E_Lap/1', 'energy_lap/1');

    % Potencia de deploy (realimentacao para bateria)
    add_line(hdl_path, 'Deploy_Switch/1', 'P_deploy/1');
end

%% =========================================================
%  CONEXOES PLANTA <-> CONTROLADOR
%  =========================================================

if hasHDLVerifier
    % Para HDL Cosim, as conexoes sao configuradas dentro do bloco
    % Aqui conectamos apenas as portas externas da planta
    % O usuario deve mapear os sinais dentro do bloco HDL Cosim

    % Conectar saidas da planta a entradas do bloco HDL Cosim
    % (o bloco precisa ser configurado manualmente apos criacao)

    % Criar ports de conexao intermediarios
    add_block('simulink/Signal Routing/Goto', [modelName '/Goto_Speed']);
    set_param([modelName '/Goto_Speed'], 'GotoTag', 'speed_rpm');
    add_line(modelName, 'Plant/1', 'Goto_Speed/1');

    add_block('simulink/Signal Routing/Goto', [modelName '/Goto_Brake']);
    set_param([modelName '/Goto_Brake'], 'GotoTag', 'brake_pres');
    add_line(modelName, 'Plant/2', 'Goto_Brake/1');

    add_block('simulink/Signal Routing/Goto', [modelName '/Goto_Throttle']);
    set_param([modelName '/Goto_Throttle'], 'GotoTag', 'throttle');
    add_line(modelName, 'Plant/3', 'Goto_Throttle/1');

    add_block('simulink/Signal Routing/Goto', [modelName '/Goto_SoC']);
    set_param([modelName '/Goto_SoC'], 'GotoTag', 'soc_adc');
    add_line(modelName, 'Plant/4', 'Goto_SoC/1');

    add_block('simulink/Signal Routing/Goto', [modelName '/Goto_Turbo']);
    set_param([modelName '/Goto_Turbo'], 'GotoTag', 'turbo_rpm');
    add_line(modelName, 'Plant/5', 'Goto_Turbo/1');

    add_block('simulink/Signal Routing/Goto', [modelName '/Goto_Lap']);
    set_param([modelName '/Goto_Lap'], 'GotoTag', 'lap_reset');
    add_line(modelName, 'Plant/9', 'Goto_Lap/1');

    % P_deploy_in: sem realimentacao automatica no modo HDL.
    % Usuario deve conectar manualmente saida PWM do HDL a esta entrada,
    % ou alimentar com 0 para desabilitar descarga.
    add_block('simulink/Sources/Constant', [modelName '/P_Deploy_Zero']);
    set_param([modelName '/P_Deploy_Zero'], 'Value', '0');
    add_line(modelName, 'P_Deploy_Zero/1', 'Plant/1');

else
    % Placeholder: conexoes diretas
    add_line(modelName, 'Plant/1', 'VHDL_Controller/1');  % speed_rpm
    add_line(modelName, 'Plant/2', 'VHDL_Controller/2');  % brake_pres
    add_line(modelName, 'Plant/3', 'VHDL_Controller/3');  % throttle
    add_line(modelName, 'Plant/4', 'VHDL_Controller/4');  % soc_adc
    add_line(modelName, 'Plant/5', 'VHDL_Controller/5');  % turbo_rpm
    add_line(modelName, 'Plant/9', 'VHDL_Controller/6');  % lap_reset

    % Realimentacao P_deploy (saida 4 do controlador) -> entrada da planta
    add_line(modelName, 'VHDL_Controller/4', 'Plant/1');  % P_deploy
end

%% =========================================================
%  SCOPES DE MONITORAMENTO
%  =========================================================

% Scope: SoC
add_block('simulink/Sinks/Scope', [modelName '/Scope_SoC']);
set_param([modelName '/Scope_SoC'], 'NumInputPorts', '1');
add_line(modelName, 'Plant/6', 'Scope_SoC/1');  % soc_percent

% Scope: Potencias
add_block('simulink/Sinks/Scope', [modelName '/Scope_Power']);
set_param([modelName '/Scope_Power'], 'NumInputPorts', '2');
add_line(modelName, 'Plant/7', 'Scope_Power/1');  % P_mguk
add_line(modelName, 'Plant/8', 'Scope_Power/2');  % P_mguh

% Scope: Modo ERS e Energia (do controlador)
if ~hasHDLVerifier
    add_block('simulink/Sinks/Scope', [modelName '/Scope_ERS']);
    set_param([modelName '/Scope_ERS'], 'NumInputPorts', '3');
    add_line(modelName, 'VHDL_Controller/2', 'Scope_ERS/1');  % ers_mode
    add_line(modelName, 'VHDL_Controller/3', 'Scope_ERS/2');  % energy_lap
    add_line(modelName, 'VHDL_Controller/4', 'Scope_ERS/3');  % P_deploy
end

% To Workspace: exportar dados
add_block('simulink/Sinks/To Workspace', [modelName '/ToWS_SoC']);
set_param([modelName '/ToWS_SoC'], 'VariableName', 'soc_data', 'SaveFormat', 'Timeseries');
add_line(modelName, 'Plant/6', 'ToWS_SoC/1');

add_block('simulink/Sinks/To Workspace', [modelName '/ToWS_P_mguk']);
set_param([modelName '/ToWS_P_mguk'], 'VariableName', 'p_mguk_data', 'SaveFormat', 'Timeseries');
add_line(modelName, 'Plant/7', 'ToWS_P_mguk/1');

add_block('simulink/Sinks/To Workspace', [modelName '/ToWS_P_mguh']);
set_param([modelName '/ToWS_P_mguh'], 'VariableName', 'p_mguh_data', 'SaveFormat', 'Timeseries');
add_line(modelName, 'Plant/8', 'ToWS_P_mguh/1');

% P_deploy e energia por volta (somente modo placeholder)
if ~hasHDLVerifier
    add_block('simulink/Sinks/To Workspace', [modelName '/ToWS_P_deploy']);
    set_param([modelName '/ToWS_P_deploy'], 'VariableName', 'p_deploy_data', ...
        'SaveFormat', 'Timeseries');
    add_line(modelName, 'VHDL_Controller/4', 'ToWS_P_deploy/1');

    add_block('simulink/Sinks/To Workspace', [modelName '/ToWS_E_lap']);
    set_param([modelName '/ToWS_E_lap'], 'VariableName', 'e_lap_data', ...
        'SaveFormat', 'Timeseries');
    add_line(modelName, 'VHDL_Controller/3', 'ToWS_E_lap/1');
end

% Scope: Cenario
add_block('simulink/Sinks/Scope', [modelName '/Scope_Scenario']);
set_param([modelName '/Scope_Scenario'], 'NumInputPorts', '4');
add_line(modelName, 'Plant/1', 'Scope_Scenario/1');  % speed
add_line(modelName, 'Plant/2', 'Scope_Scenario/2');  % brake
add_line(modelName, 'Plant/3', 'Scope_Scenario/3');  % throttle
add_line(modelName, 'Plant/5', 'Scope_Scenario/4');  % turbo

%% =========================================================
%  LAYOUT
%  =========================================================
set_param([modelName '/Plant'], 'Position', [100, 100, 350, 400]);

if hasHDLVerifier
    set_param([modelName '/HDL_Cosim'], 'Position', [500, 150, 700, 350]);
else
    set_param([modelName '/VHDL_Controller'], 'Position', [500, 150, 700, 350]);
end

set_param([modelName '/Scope_SoC'],      'Position', [850, 100, 900, 140]);
set_param([modelName '/Scope_Power'],    'Position', [850, 160, 900, 200]);
set_param([modelName '/Scope_Scenario'], 'Position', [850, 220, 900, 280]);
set_param([modelName '/ToWS_SoC'],       'Position', [850, 300, 950, 330]);
set_param([modelName '/ToWS_P_mguk'],    'Position', [850, 340, 950, 370]);
set_param([modelName '/ToWS_P_mguh'],    'Position', [850, 380, 950, 410]);

%% =========================================================
%  SALVAR
%  =========================================================
save_system(modelName);
fprintf('\nModelo %s.slx criado com sucesso!\n', modelName);

if hasHDLVerifier
    fprintf('\n=== MODO CO-SIMULACAO REAL ===\n');
    fprintf('Passos para executar:\n');
    fprintf('  1. No ModelSim: do sim_cosim.do\n');
    fprintf('  2. No MATLAB: abrir cosim_top.slx\n');
    fprintf('  3. Configurar bloco HDL Cosim (ver docs/04_cosimulacao.md)\n');
    fprintf('  4. Iniciar simulacao no Simulink\n');
else
    fprintf('\n=== MODO PLACEHOLDER (sem HDL Verifier) ===\n');
    fprintf('O modelo usa um controlador simplificado em Simulink.\n');
    fprintf('Para testar: sim(''cosim_top'')\n');
    fprintf('Para co-simulacao real, instale HDL Verifier.\n');
end
