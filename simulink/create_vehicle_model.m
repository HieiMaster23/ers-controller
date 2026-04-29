%% create_vehicle_model.m
% Cria o modelo Simulink vehicle_model.slx programaticamente.
% Executar este script no MATLAB para gerar o arquivo .slx.
%
% Autor: Rafael
% Data: 2026-04-02
% Projeto: ERS Simulation Project

%% Limpar ambiente
close all; clc;

modelName = 'vehicle_model';

% Fecha modelo se ja estiver aberto
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end

% Remove arquivo existente
if exist([modelName '.slx'], 'file')
    delete([modelName '.slx']);
end

%% =========================================================
%  PARAMETROS DO MODELO
%  =========================================================
% Salva parametros no workspace para uso nos blocos

% Bateria
V_bus_nominal  = 400;        % V - tensao nominal do barramento HV
Q_max_battery  = 4e6;        % J - capacidade maxima da bateria
SoC_inicial    = 0.70;       % 70% de carga inicial
R_internal     = 0.05;       % Ohm - resistencia interna

% MGU-K
K_mguk_torque  = 0.8;        % Nm/bar de pressao de freio
P_max_mguk     = 120e3;      % W - potencia maxima (120 kW)
eta_mguk       = 0.90;       % rendimento do MGU-K

% MGU-H
k_turbo        = 1.5e-5;     % W/RPM^2 - coeficiente de potencia do turbo
P_max_mguh     = 50e3;       % W - potencia maxima de harvest do MGU-H

% Simulacao
Ts             = 1e-3;       % s - passo de simulacao (1 ms)
T_volta        = 60;         % s - duracao de uma volta
T_sim          = 180;        % s - tempo total de simulacao (3 voltas)

% Salvar parametros no workspace
assignin('base', 'V_bus_nominal', V_bus_nominal);
assignin('base', 'Q_max_battery', Q_max_battery);
assignin('base', 'SoC_inicial',   SoC_inicial);
assignin('base', 'R_internal',    R_internal);
assignin('base', 'K_mguk_torque', K_mguk_torque);
assignin('base', 'P_max_mguk',    P_max_mguk);
assignin('base', 'eta_mguk',      eta_mguk);
assignin('base', 'k_turbo',       k_turbo);
assignin('base', 'P_max_mguh',    P_max_mguh);
assignin('base', 'Ts',            Ts);
assignin('base', 'T_volta',       T_volta);
assignin('base', 'T_sim',         T_sim);

%% =========================================================
%  CRIAR MODELO
%  =========================================================
new_system(modelName);
open_system(modelName);

% Configurar solver
set_param(modelName, 'Solver', 'ode4');
set_param(modelName, 'FixedStep', num2str(Ts));
set_param(modelName, 'StopTime', num2str(T_sim));

%% =========================================================
%  SUBSISTEMA: CENARIO DE CORRIDA
%  =========================================================
% Gera sinais que simulam uma volta: speed_rpm, brake_pressure,
% throttle_pos, turbo_rpm

cenario_path = [modelName '/Race_Scenario'];
add_block('simulink/Ports & Subsystems/Subsystem', cenario_path);

% Remover blocos padrao do subsistema
delete_line(cenario_path, 'In1/1', 'Out1/1');
delete_block([cenario_path '/In1']);
delete_block([cenario_path '/Out1']);

% Clock para gerar tempo de volta (modular por T_volta)
add_block('simulink/Sources/Clock', [cenario_path '/Clock']);
add_block('simulink/Math Operations/Math Function', [cenario_path '/Mod']);
set_param([cenario_path '/Mod'], 'Operator', 'mod');
add_block('simulink/Sources/Constant', [cenario_path '/T_volta']);
set_param([cenario_path '/T_volta'], 'Value', 'T_volta');

add_line(cenario_path, 'Clock/1', 'Mod/1');
add_line(cenario_path, 'T_volta/1', 'Mod/2');

% -- Perfil de velocidade (speed_rpm): Lookup Table
% Trecho: aceleracao (0-30s), frenagem (30-35s), curva (35-45s), saida (45-60s)
add_block('simulink/Lookup Tables/1-D Lookup Table', [cenario_path '/Speed_Profile']);
set_param([cenario_path '/Speed_Profile'], ...
    'Table',      '[3000, 15000, 18000, 18000, 8000, 5000, 5000, 8000, 15000, 3000]', ...
    'BreakpointsForDimension1', '[0, 10, 20, 28, 32, 35, 38, 45, 55, 60]');
add_line(cenario_path, 'Mod/1', 'Speed_Profile/1');

% -- Perfil de frenagem (brake_pressure): Lookup Table (0-100 bar -> 0-4095)
add_block('simulink/Lookup Tables/1-D Lookup Table', [cenario_path '/Brake_Profile']);
set_param([cenario_path '/Brake_Profile'], ...
    'Table',      '[0, 0, 0, 0, 3500, 4095, 2000, 0, 0, 0]', ...
    'BreakpointsForDimension1', '[0, 10, 20, 28, 30, 33, 36, 40, 50, 60]');
add_line(cenario_path, 'Mod/1', 'Brake_Profile/1');

% -- Perfil de acelerador (throttle): Lookup Table (0-100% -> 0-4095)
add_block('simulink/Lookup Tables/1-D Lookup Table', [cenario_path '/Throttle_Profile']);
set_param([cenario_path '/Throttle_Profile'], ...
    'Table',      '[2048, 3500, 4095, 4095, 0, 0, 500, 2500, 4095, 2048]', ...
    'BreakpointsForDimension1', '[0, 10, 20, 28, 30, 35, 38, 45, 55, 60]');
add_line(cenario_path, 'Mod/1', 'Throttle_Profile/1');

% -- Perfil do turbo (turbo_rpm): proporcional ao throttle com dinamica
add_block('simulink/Lookup Tables/1-D Lookup Table', [cenario_path '/Turbo_Profile']);
set_param([cenario_path '/Turbo_Profile'], ...
    'Table',      '[20000, 45000, 60000, 65000, 30000, 20000, 25000, 40000, 60000, 20000]', ...
    'BreakpointsForDimension1', '[0, 10, 20, 28, 32, 36, 40, 45, 55, 60]');
add_line(cenario_path, 'Mod/1', 'Turbo_Profile/1');

% -- Saidas do subsistema
add_block('simulink/Ports & Subsystems/Out1', [cenario_path '/speed_rpm']);
add_block('simulink/Ports & Subsystems/Out1', [cenario_path '/brake_pres']);
add_block('simulink/Ports & Subsystems/Out1', [cenario_path '/throttle']);
add_block('simulink/Ports & Subsystems/Out1', [cenario_path '/turbo_rpm']);

add_line(cenario_path, 'Speed_Profile/1',   'speed_rpm/1');
add_line(cenario_path, 'Brake_Profile/1',   'brake_pres/1');
add_line(cenario_path, 'Throttle_Profile/1','throttle/1');
add_line(cenario_path, 'Turbo_Profile/1',   'turbo_rpm/1');

%% =========================================================
%  SUBSISTEMA: MGU-K
%  =========================================================
% Modelo simplificado: potencia = K_mguk_torque * brake_bar * omega * eta
% Saida: apenas potencia (W). Conversao P->I feita na bateria.

mguk_path = [modelName '/MGU_K'];
add_block('simulink/Ports & Subsystems/Subsystem', mguk_path);

delete_line(mguk_path, 'In1/1', 'Out1/1');
delete_block([mguk_path '/In1']);
delete_block([mguk_path '/Out1']);

% Entradas
add_block('simulink/Ports & Subsystems/In1', [mguk_path '/brake_pres']);
add_block('simulink/Ports & Subsystems/In1', [mguk_path '/speed_rpm']);

% Converter brake_pres de escala ADC (0-4095) para bar (0-100)
add_block('simulink/Math Operations/Gain', [mguk_path '/ADC_to_bar']);
set_param([mguk_path '/ADC_to_bar'], 'Gain', '100/4095');

% Converter speed_rpm para rad/s (rpm * 2*pi/60)
add_block('simulink/Math Operations/Gain', [mguk_path '/RPM_to_rads']);
set_param([mguk_path '/RPM_to_rads'], 'Gain', '2*pi/60');

% Torque = K_mguk_torque * brake_bar
add_block('simulink/Math Operations/Gain', [mguk_path '/K_torque']);
set_param([mguk_path '/K_torque'], 'Gain', 'K_mguk_torque');

% Potencia = Torque * omega
add_block('simulink/Math Operations/Product', [mguk_path '/P_mech']);

% Potencia eletrica = P_mech * eta
add_block('simulink/Math Operations/Gain', [mguk_path '/Eta']);
set_param([mguk_path '/Eta'], 'Gain', 'eta_mguk');

% Saturacao em P_max_mguk
add_block('simulink/Discontinuities/Saturation', [mguk_path '/Sat_P']);
set_param([mguk_path '/Sat_P'], 'UpperLimit', 'P_max_mguk', 'LowerLimit', '0');

% Saida: potencia eletrica (W)
add_block('simulink/Ports & Subsystems/Out1', [mguk_path '/P_mguk']);

% Conexoes
add_line(mguk_path, 'brake_pres/1', 'ADC_to_bar/1');
add_line(mguk_path, 'speed_rpm/1',  'RPM_to_rads/1');
add_line(mguk_path, 'ADC_to_bar/1', 'K_torque/1');
add_line(mguk_path, 'K_torque/1',   'P_mech/1');
add_line(mguk_path, 'RPM_to_rads/1','P_mech/2');
add_line(mguk_path, 'P_mech/1',     'Eta/1');
add_line(mguk_path, 'Eta/1',        'Sat_P/1');
add_line(mguk_path, 'Sat_P/1',      'P_mguk/1');

%% =========================================================
%  SUBSISTEMA: MGU-H
%  =========================================================
% Potencia = k_turbo * turbo_rpm^2, saturada em P_max_mguh
% Saida: apenas potencia (W). Conversao P->I feita na bateria.

mguh_path = [modelName '/MGU_H'];
add_block('simulink/Ports & Subsystems/Subsystem', mguh_path);

delete_line(mguh_path, 'In1/1', 'Out1/1');
delete_block([mguh_path '/In1']);
delete_block([mguh_path '/Out1']);

% Entrada
add_block('simulink/Ports & Subsystems/In1', [mguh_path '/turbo_rpm']);

% turbo_rpm^2
add_block('simulink/Math Operations/Math Function', [mguh_path '/Square']);
set_param([mguh_path '/Square'], 'Operator', 'square');

% * k_turbo
add_block('simulink/Math Operations/Gain', [mguh_path '/K_turbo']);
set_param([mguh_path '/K_turbo'], 'Gain', 'k_turbo');

% Saturacao
add_block('simulink/Discontinuities/Saturation', [mguh_path '/Sat_P']);
set_param([mguh_path '/Sat_P'], 'UpperLimit', 'P_max_mguh', 'LowerLimit', '0');

% Saida: potencia eletrica (W)
add_block('simulink/Ports & Subsystems/Out1', [mguh_path '/P_mguh']);

% Conexoes
add_line(mguh_path, 'turbo_rpm/1', 'Square/1');
add_line(mguh_path, 'Square/1',    'K_turbo/1');
add_line(mguh_path, 'K_turbo/1',   'Sat_P/1');
add_line(mguh_path, 'Sat_P/1',     'P_mguh/1');

%% =========================================================
%  SUBSISTEMA: BATERIA HV
%  =========================================================
% Modelo RC de 1a ordem:
%   V_oc = f(SoC) ~= V_bus_nominal (simplificado como constante)
%   V_terminal = V_oc - R_internal * I_total
%   dSoC/dt = -I_total / (Q_max_battery / V_bus_nominal)
%   Q_max_As = Q_max_battery / V_bus_nominal = 10000 As

battery_path = [modelName '/Battery_HV'];
add_block('simulink/Ports & Subsystems/Subsystem', battery_path);

delete_line(battery_path, 'In1/1', 'Out1/1');
delete_block([battery_path '/In1']);
delete_block([battery_path '/Out1']);

% Entradas: potencias dos dois MGUs (W)
add_block('simulink/Ports & Subsystems/In1', [battery_path '/P_mguk']);
add_block('simulink/Ports & Subsystems/In1', [battery_path '/P_mguh']);

% Soma das potencias (harvest total)
add_block('simulink/Math Operations/Add', [battery_path '/Sum_P']);
add_line(battery_path, 'P_mguk/1', 'Sum_P/1');
add_line(battery_path, 'P_mguh/1', 'Sum_P/2');

% Converter potencia total para corrente: I = P_total / V_bus
add_block('simulink/Math Operations/Gain', [battery_path '/P_to_I']);
set_param([battery_path '/P_to_I'], 'Gain', '1/V_bus_nominal');
add_line(battery_path, 'Sum_P/1', 'P_to_I/1');

% Integrador de SoC: dSoC/dt = I_total / Q_max_As
% Q_max_As = Q_max_battery / V_bus_nominal = 10000 As
add_block('simulink/Math Operations/Gain', [battery_path '/I_to_dSoC']);
set_param([battery_path '/I_to_dSoC'], 'Gain', '1 / (Q_max_battery / V_bus_nominal)');

add_block('simulink/Continuous/Integrator', [battery_path '/SoC_Integrator']);
set_param([battery_path '/SoC_Integrator'], ...
    'InitialCondition', 'SoC_inicial', ...
    'LimitOutput', 'on', ...
    'UpperSaturationLimit', '0.95', ...
    'LowerSaturationLimit', '0.20');

add_line(battery_path, 'P_to_I/1',       'I_to_dSoC/1');
add_line(battery_path, 'I_to_dSoC/1',    'SoC_Integrator/1');

% Converter SoC (0-1) para escala ADC (0-4095) para o VHDL
add_block('simulink/Math Operations/Gain', [battery_path '/SoC_to_ADC']);
set_param([battery_path '/SoC_to_ADC'], 'Gain', '4095');

add_line(battery_path, 'SoC_Integrator/1', 'SoC_to_ADC/1');

% V_terminal = V_oc - R * I (simplificado)
add_block('simulink/Math Operations/Gain', [battery_path '/R_drop']);
set_param([battery_path '/R_drop'], 'Gain', 'R_internal');

add_block('simulink/Sources/Constant', [battery_path '/V_oc']);
set_param([battery_path '/V_oc'], 'Value', 'V_bus_nominal');

add_block('simulink/Math Operations/Subtract', [battery_path '/V_term_calc']);
add_line(battery_path, 'P_to_I/1',  'R_drop/1');
add_line(battery_path, 'V_oc/1',    'V_term_calc/1');
add_line(battery_path, 'R_drop/1',  'V_term_calc/2');

% Saidas
add_block('simulink/Ports & Subsystems/Out1', [battery_path '/soc_adc']);
add_block('simulink/Ports & Subsystems/Out1', [battery_path '/soc_percent']);
add_block('simulink/Ports & Subsystems/Out1', [battery_path '/V_terminal']);

add_line(battery_path, 'SoC_to_ADC/1',      'soc_adc/1');
add_line(battery_path, 'SoC_Integrator/1',   'soc_percent/1');
add_line(battery_path, 'V_term_calc/1',       'V_terminal/1');

%% =========================================================
%  CONEXOES DO NIVEL SUPERIOR
%  =========================================================

% Race_Scenario -> MGU_K
add_line(modelName, 'Race_Scenario/2', 'MGU_K/1');    % brake_pres
add_line(modelName, 'Race_Scenario/1', 'MGU_K/2');    % speed_rpm

% Race_Scenario -> MGU_H
add_line(modelName, 'Race_Scenario/4', 'MGU_H/1');    % turbo_rpm

% MGU_K, MGU_H -> Battery (potencia, nao corrente)
add_line(modelName, 'MGU_K/1', 'Battery_HV/1');       % P_mguk
add_line(modelName, 'MGU_H/1', 'Battery_HV/2');       % P_mguh

%% =========================================================
%  SCOPES PARA MONITORAMENTO
%  =========================================================

% Scope: SoC
add_block('simulink/Sinks/Scope', [modelName '/Scope_SoC']);
set_param([modelName '/Scope_SoC'], 'NumInputPorts', '1');
add_line(modelName, 'Battery_HV/2', 'Scope_SoC/1');   % soc_percent

% Scope: Potencias
add_block('simulink/Sinks/Scope', [modelName '/Scope_Power']);
set_param([modelName '/Scope_Power'], 'NumInputPorts', '2');
add_line(modelName, 'MGU_K/1', 'Scope_Power/1');       % P_mguk
add_line(modelName, 'MGU_H/1', 'Scope_Power/2');       % P_mguh

% Scope: Sinais do cenario
add_block('simulink/Sinks/Scope', [modelName '/Scope_Scenario']);
set_param([modelName '/Scope_Scenario'], 'NumInputPorts', '4');
add_line(modelName, 'Race_Scenario/1', 'Scope_Scenario/1');  % speed
add_line(modelName, 'Race_Scenario/2', 'Scope_Scenario/2');  % brake
add_line(modelName, 'Race_Scenario/3', 'Scope_Scenario/3');  % throttle
add_line(modelName, 'Race_Scenario/4', 'Scope_Scenario/4');  % turbo

% To Workspace para exportar dados
add_block('simulink/Sinks/To Workspace', [modelName '/ToWS_SoC']);
set_param([modelName '/ToWS_SoC'], 'VariableName', 'soc_data', 'SaveFormat', 'Timeseries');
add_line(modelName, 'Battery_HV/2', 'ToWS_SoC/1');

add_block('simulink/Sinks/To Workspace', [modelName '/ToWS_P_mguk']);
set_param([modelName '/ToWS_P_mguk'], 'VariableName', 'p_mguk_data', 'SaveFormat', 'Timeseries');
add_line(modelName, 'MGU_K/1', 'ToWS_P_mguk/1');

add_block('simulink/Sinks/To Workspace', [modelName '/ToWS_P_mguh']);
set_param([modelName '/ToWS_P_mguh'], 'VariableName', 'p_mguh_data', 'SaveFormat', 'Timeseries');
add_line(modelName, 'MGU_H/1', 'ToWS_P_mguh/1');

%% =========================================================
%  SALVAR E ORGANIZAR LAYOUT
%  =========================================================
% Posicionar blocos para melhor visualizacao
set_param([modelName '/Race_Scenario'], 'Position', [100, 150, 250, 300]);
set_param([modelName '/MGU_K'],         'Position', [400, 100, 550, 200]);
set_param([modelName '/MGU_H'],         'Position', [400, 280, 550, 360]);
set_param([modelName '/Battery_HV'],    'Position', [700, 150, 850, 300]);
set_param([modelName '/Scope_SoC'],     'Position', [950, 200, 1000, 250]);
set_param([modelName '/Scope_Power'],   'Position', [950, 100, 1000, 150]);
set_param([modelName '/Scope_Scenario'],'Position', [400, 400, 450, 500]);
set_param([modelName '/ToWS_SoC'],      'Position', [950, 270, 1050, 300]);
set_param([modelName '/ToWS_P_mguk'],   'Position', [700, 50, 800, 80]);
set_param([modelName '/ToWS_P_mguh'],   'Position', [700, 380, 800, 410]);

save_system(modelName);
fprintf('Modelo %s.slx criado com sucesso!\n', modelName);
fprintf('Execute "sim(''%s'')" para rodar a simulacao standalone.\n', modelName);
