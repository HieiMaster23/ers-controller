%% validate_standalone.m
% Validacao standalone do modelo fisico usando MATLAB puro (sem Simulink).
% Resolve as equacoes do modelo numericamente e plota os sinais
% para verificar que o comportamento esta dentro do esperado.
%
% Autor: Rafael
% Data: 2026-04-02
% Projeto: ERS Simulation Project

clear; close all; clc;

%% =========================================================
%  PARAMETROS
%  =========================================================
V_bus       = 400;           % V
Q_max_J     = 4e6;           % J (capacidade da bateria)
Q_max_As    = Q_max_J / V_bus; % 10000 As
SoC_0       = 0.70;          % 70%
R_int       = 0.05;          % Ohm

K_mguk      = 0.8;           % Nm/bar
P_max_mguk  = 120e3;         % W
eta_mguk    = 0.90;

k_turbo     = 1.5e-5;        % W/RPM^2
P_max_mguh  = 50e3;          % W

T_volta     = 60;            % s
T_sim       = 180;           % s (3 voltas)
dt          = 1e-3;          % s

%% =========================================================
%  CENARIO DE CORRIDA (Lookup Tables)
%  =========================================================
% Breakpoints e valores (mesmos do Simulink)
bp_time     = [0, 10, 20, 28, 32, 35, 38, 45, 55, 60];

speed_vals  = [3000, 15000, 18000, 18000, 8000, 5000, 5000, 8000, 15000, 3000];  % RPM
brake_vals  = [0, 0, 0, 0, 3500, 4095, 2000, 0, 0, 0];          % ADC 0-4095
throt_vals  = [2048, 3500, 4095, 4095, 0, 0, 500, 2500, 4095, 2048]; % ADC 0-4095
turbo_vals  = [20000, 45000, 60000, 65000, 30000, 20000, 25000, 40000, 60000, 20000]; % RPM

%% =========================================================
%  SIMULACAO
%  =========================================================
t = 0:dt:T_sim;
N = length(t);

% Vetores de saida
speed_rpm   = zeros(1, N);
brake_pres  = zeros(1, N);
throttle    = zeros(1, N);
turbo_rpm   = zeros(1, N);
P_mguk      = zeros(1, N);
P_mguh      = zeros(1, N);
I_mguk      = zeros(1, N);
I_mguh      = zeros(1, N);
I_total     = zeros(1, N);
SoC         = zeros(1, N);
V_term      = zeros(1, N);
E_deploy    = zeros(1, N);  % energia deployada acumulada na volta

SoC(1) = SoC_0;

for k = 1:N
    % Tempo dentro da volta (modular)
    t_lap = mod(t(k), T_volta);

    % Interpolar sinais do cenario
    speed_rpm(k) = interp1(bp_time, speed_vals, t_lap, 'linear', 'extrap');
    brake_pres(k) = interp1(bp_time, brake_vals, t_lap, 'linear', 'extrap');
    throttle(k)  = interp1(bp_time, throt_vals, t_lap, 'linear', 'extrap');
    turbo_rpm(k) = interp1(bp_time, turbo_vals, t_lap, 'linear', 'extrap');

    % --- MGU-K ---
    brake_bar = brake_pres(k) * 100 / 4095;  % ADC -> bar
    omega     = speed_rpm(k) * 2 * pi / 60;  % RPM -> rad/s
    torque_k  = K_mguk * brake_bar;           % Nm
    P_mech_k  = torque_k * omega;             % W
    P_elec_k  = P_mech_k * eta_mguk;          % W
    P_mguk(k) = min(P_elec_k, P_max_mguk);   % Saturacao
    I_mguk(k) = P_mguk(k) / V_bus;           % A

    % --- MGU-H ---
    P_turbo    = k_turbo * turbo_rpm(k)^2;    % W
    P_mguh(k)  = min(P_turbo, P_max_mguh);    % Saturacao
    I_mguh(k)  = P_mguh(k) / V_bus;           % A

    % --- Bateria ---
    % Corrente positiva = carga (harvest), negativa = descarga (deploy)
    % Neste modelo standalone, so temos harvest (sem controlador VHDL)
    I_total(k) = I_mguk(k) + I_mguh(k);

    V_term(k) = V_bus - R_int * I_total(k);

    % Integrar SoC
    if k < N
        dSoC = I_total(k) / Q_max_As * dt;
        SoC(k+1) = SoC(k) + dSoC;
        % Clamping
        SoC(k+1) = max(0.20, min(0.95, SoC(k+1)));
    end

    % Reset de energia acumulada a cada volta
    if k > 1 && mod(t(k), T_volta) < mod(t(k-1), T_volta)
        E_deploy(k) = 0;
    elseif k > 1
        E_deploy(k) = E_deploy(k-1);
    end
end

%% =========================================================
%  GRAFICOS
%  =========================================================
figure('Name', 'ERS Standalone Validation', 'Position', [50, 50, 1200, 900]);

% 1. Cenario de corrida
subplot(3,2,1);
plot(t, speed_rpm/1000, 'b', 'LineWidth', 1.2);
xlabel('Tempo (s)'); ylabel('Velocidade (x1000 RPM)');
title('Perfil de Velocidade'); grid on;
xline([60, 120], '--r', 'Volta');

subplot(3,2,2);
yyaxis left;
plot(t, brake_pres, 'r', 'LineWidth', 1.2);
ylabel('Freio (ADC)');
yyaxis right;
plot(t, throttle, 'g', 'LineWidth', 1.2);
ylabel('Acelerador (ADC)');
xlabel('Tempo (s)');
title('Freio vs Acelerador'); grid on;
legend('Freio', 'Acelerador');

% 2. Potencias
subplot(3,2,3);
plot(t, P_mguk/1000, 'b', t, P_mguh/1000, 'r', 'LineWidth', 1.2);
xlabel('Tempo (s)'); ylabel('Potencia (kW)');
title('Potencia dos MGUs');
legend('MGU-K', 'MGU-H'); grid on;
yline(120, '--k', '120 kW limit');
xline([60, 120], '--r', 'Volta');

% 3. Correntes
subplot(3,2,4);
plot(t, I_mguk, 'b', t, I_mguh, 'r', t, I_total, 'k--', 'LineWidth', 1.2);
xlabel('Tempo (s)'); ylabel('Corrente (A)');
title('Correntes de Harvest');
legend('I_{MGU-K}', 'I_{MGU-H}', 'I_{total}'); grid on;
xline([60, 120], '--r', 'Volta');

% 4. SoC
subplot(3,2,5);
plot(t, SoC*100, 'b', 'LineWidth', 1.5);
xlabel('Tempo (s)'); ylabel('SoC (%)');
title('Estado de Carga da Bateria');
yline([20, 95], '--r', {'Min 20%', 'Max 95%'});
grid on;
xline([60, 120], '--r', 'Volta');

% 5. Turbo RPM
subplot(3,2,6);
plot(t, turbo_rpm/1000, 'm', 'LineWidth', 1.2);
xlabel('Tempo (s)'); ylabel('Turbo (x1000 RPM)');
title('RPM do Turbocompressor');
yline(40, '--k', '40k RPM (harvest threshold)');
grid on;
xline([60, 120], '--r', 'Volta');

sgtitle('Validacao Standalone - Modelo Fisico ERS (3 voltas)', 'FontSize', 14);

%% =========================================================
%  RELATORIO NO CONSOLE
%  =========================================================
fprintf('\n========================================\n');
fprintf('  RELATORIO DE VALIDACAO STANDALONE\n');
fprintf('========================================\n');
fprintf('Duracao simulada:     %.0f s (%.0f voltas)\n', T_sim, T_sim/T_volta);
fprintf('Passo de simulacao:   %.1f ms\n', dt*1000);
fprintf('\n--- Estado de Carga ---\n');
fprintf('SoC inicial:          %.1f%%\n', SoC_0*100);
fprintf('SoC final:            %.1f%%\n', SoC(end)*100);
fprintf('SoC minimo:           %.1f%%\n', min(SoC)*100);
fprintf('SoC maximo:           %.1f%%\n', max(SoC)*100);
fprintf('SoC dentro limites:   %s\n', ...
    iff(min(SoC)>=0.20 && max(SoC)<=0.95, 'SIM', 'NAO'));

fprintf('\n--- Potencias ---\n');
fprintf('P_mguk maxima:        %.1f kW (limite: 120 kW)\n', max(P_mguk)/1000);
fprintf('P_mguh maxima:        %.1f kW (limite: 50 kW)\n', max(P_mguh)/1000);
fprintf('P_mguk dentro limite: %s\n', iff(max(P_mguk)<=P_max_mguk, 'SIM', 'NAO'));
fprintf('P_mguh dentro limite: %s\n', iff(max(P_mguh)<=P_max_mguh, 'SIM', 'NAO'));

fprintf('\n--- Correntes ---\n');
fprintf('I_total maxima:       %.1f A\n', max(I_total));
fprintf('I_total media:        %.1f A\n', mean(I_total));

fprintf('\n--- Cenario ---\n');
fprintf('Velocidade max:       %.0f RPM\n', max(speed_rpm));
fprintf('Turbo max:            %.0f RPM\n', max(turbo_rpm));
fprintf('\n========================================\n');
fprintf('Validacao standalone concluida.\n');
fprintf('Nota: Este modelo so simula harvest (sem deploy).\n');
fprintf('O deploy sera controlado pelo VHDL na co-simulacao.\n');
fprintf('========================================\n');

%% Funcao auxiliar
function result = iff(condition, trueVal, falseVal)
    if condition
        result = trueVal;
    else
        result = falseVal;
    end
end
