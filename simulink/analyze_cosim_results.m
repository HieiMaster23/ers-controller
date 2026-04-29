%% analyze_cosim_results.m
% Analisa os dados exportados da co-simulacao (ou do placeholder).
% Plota graficos e verifica limites do regulamento.
%
% Executar apos rodar a simulacao de cosim_top.slx.
% Requer: soc_data, p_mguk_data, p_mguh_data no workspace (Timeseries).
% Opcional (modo placeholder): p_deploy_data, e_lap_data.
%
% Autor: Rafael
% Data: 2026-04-06
% Projeto: ERS Simulation Project

close all; clc;

%% Parametros do regulamento
ENERGY_MAX_J  = 4e6;     % 4 MJ por volta
P_MAX_DEPLOY  = 120e3;   % 120 kW
P_MAX_MGUH    = 50e3;    % 50 kW
SOC_MIN       = 0.20;    % 20%
SOC_MAX       = 0.95;    % 95%
T_VOLTA       = 60;      % s

%% Verificar dados no workspace
% Simulink moderno retorna SimulationOutput 'out'; extrair se necessario
req_vars = {'soc_data','p_mguk_data','p_mguh_data'};
opt_vars = {'p_deploy_data','e_lap_data'};

missing = ~all(cellfun(@(v) exist(v,'var'), req_vars));
if missing
    if evalin('base','exist(''out'',''var'')') && ...
            isa(evalin('base','out'), 'Simulink.SimulationOutput')
        out = evalin('base','out');
        for i = 1:numel(req_vars)
            v = req_vars{i};
            eval([v ' = out.' v ';']);
            assignin('base', v, eval(v));
        end
        for i = 1:numel(opt_vars)
            v = opt_vars{i};
            try
                eval([v ' = out.' v ';']);
                assignin('base', v, eval(v));
            catch
                % Variavel opcional nao existe; ignorar.
            end
        end
        fprintf('Dados extraidos do objeto SimulationOutput ''out''.\n');
    else
        error(['Dados nao encontrados. Execute a simulacao de cosim_top.slx primeiro ' ...
               '(ex: out = sim(''cosim_top'')).']);
    end
end

has_deploy = exist('p_deploy_data','var') == 1;
has_elap   = exist('e_lap_data','var') == 1;

%% Extrair dados
t_soc   = soc_data.Time;
soc     = soc_data.Data * 100; % converter para %

t_pk    = p_mguk_data.Time;
p_mguk  = p_mguk_data.Data;

t_ph    = p_mguh_data.Time;
p_mguh  = p_mguh_data.Data;

if has_deploy
    t_pd    = p_deploy_data.Time;
    p_deploy = p_deploy_data.Data;
end
if has_elap
    t_el   = e_lap_data.Time;
    e_lap  = e_lap_data.Data;
end

T_sim   = t_soc(end);
n_voltas = floor(T_sim / T_VOLTA);

%% =========================================================
%  GRAFICOS
%  =========================================================
figure('Name', 'Resultados da Co-Simulacao ERS', 'Position', [50, 50, 1280, 900]);

% 1. SoC
subplot(3,2,1);
plot(t_soc, soc, 'b', 'LineWidth', 1.5);
hold on;
yline(SOC_MIN*100, '--r', 'Min 20%');
yline(SOC_MAX*100, '--r', 'Max 95%');
for v = 1:n_voltas
    xline(v*T_VOLTA, '--', ['V' num2str(v)], 'Color', [0.5 0.5 0.5]);
end
xlabel('Tempo (s)'); ylabel('SoC (%)');
title('Estado de Carga da Bateria');
grid on; ylim([10 100]);

% 2. Potencia MGU-K (harvest) + P_deploy (se houver)
subplot(3,2,2);
plot(t_pk, p_mguk/1000, 'b', 'LineWidth', 1.2, 'DisplayName', 'P_{MGU-K} (harvest)');
hold on;
if has_deploy
    plot(t_pd, p_deploy/1000, 'm', 'LineWidth', 1.2, 'DisplayName', 'P_{deploy}');
end
yline(P_MAX_DEPLOY/1000, '--r', '120 kW');
for v = 1:n_voltas
    xline(v*T_VOLTA, '--', '', 'Color', [0.5 0.5 0.5]);
end
xlabel('Tempo (s)'); ylabel('Potencia (kW)');
title('Potencia MGU-K (Harvest) e Deploy');
legend('Location', 'best'); grid on;

% 3. Potencia MGU-H
subplot(3,2,3);
plot(t_ph, p_mguh/1000, 'r', 'LineWidth', 1.2);
hold on;
yline(P_MAX_MGUH/1000, '--r', '50 kW');
for v = 1:n_voltas
    xline(v*T_VOLTA, '--', '', 'Color', [0.5 0.5 0.5]);
end
xlabel('Tempo (s)'); ylabel('Potencia (kW)');
title('Potencia MGU-H (Turbo Harvest)');
grid on;

% 4. Balanco energetico instantaneo
subplot(3,2,4);
t_common = t_pk;
p_harvest_total = p_mguk + interp1(t_ph, p_mguh, t_pk, 'linear', 0);
plot(t_common, p_harvest_total/1000, 'k', 'LineWidth', 1.2, ...
     'DisplayName', 'Harvest total');
hold on;
if has_deploy
    p_dep_interp = interp1(t_pd, p_deploy, t_common, 'linear', 0);
    p_net = p_harvest_total - p_dep_interp;
    plot(t_common, p_net/1000, 'g', 'LineWidth', 1.2, ...
         'DisplayName', 'Liquido (harvest-deploy)');
end
yline(0, ':k');
for v = 1:n_voltas
    xline(v*T_VOLTA, '--', '', 'Color', [0.5 0.5 0.5]);
end
xlabel('Tempo (s)'); ylabel('Potencia (kW)');
title('Balanco de Potencia da Bateria');
legend('Location', 'best'); grid on;

% 5. Energia gasta por volta (deploy acumulado)
subplot(3,2,5);
if has_deploy
    % Reset por volta do acumulado de deploy
    E_dep = cumtrapz(t_pd, p_deploy);
    E_dep_per_lap = E_dep;
    for v = 1:n_voltas
        idx = t_pd >= v*T_VOLTA;
        if any(idx)
            E_dep_per_lap(idx) = E_dep(idx) - E_dep(find(idx,1));
        end
    end
    plot(t_pd, E_dep_per_lap/1e6, 'm', 'LineWidth', 1.5, ...
         'DisplayName', 'Deploy (acumulado/volta)');
elseif has_elap
    plot(t_el, e_lap/1e6, 'm', 'LineWidth', 1.5, ...
         'DisplayName', 'E_{volta} (do controlador)');
end
hold on;
% Harvest acumulada por volta (referencia)
E_harvest = cumtrapz(t_common, p_harvest_total);
E_harvest_lap = E_harvest;
for v = 1:n_voltas
    idx = t_common >= v*T_VOLTA;
    if any(idx)
        E_harvest_lap(idx) = E_harvest(idx) - E_harvest(find(idx,1));
    end
end
plot(t_common, E_harvest_lap/1e6, 'g', 'LineWidth', 1.2, ...
     'DisplayName', 'Harvest (acumulado/volta)');
yline(ENERGY_MAX_J/1e6, '--r', '4 MJ');
for v = 1:n_voltas
    xline(v*T_VOLTA, '--', '', 'Color', [0.5 0.5 0.5]);
end
xlabel('Tempo (s)'); ylabel('Energia (MJ)');
title('Energia Acumulada por Volta');
legend('Location', 'best'); grid on;

% 6. Resumo textual
subplot(3,2,6);
axis off;
text(0.05, 0.95, 'RELATORIO DO REGULAMENTO', ...
    'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'top');

soc_ok = min(soc) >= SOC_MIN*100 - 0.5 && max(soc) <= SOC_MAX*100 + 0.5;
pk_ok  = max(p_mguk) <= P_MAX_DEPLOY * 1.001;
ph_ok  = max(p_mguh) <= P_MAX_MGUH * 1.001;

if has_deploy
    E_dep_max = max(E_dep_per_lap);
    e_ok = E_dep_max <= ENERGY_MAX_J * 1.001;
    pd_ok = max(p_deploy) <= P_MAX_DEPLOY * 1.001;
else
    E_dep_max = NaN;
    e_ok = true;  % sem dado, nao avaliar
    pd_ok = true;
end

approved = soc_ok && pk_ok && ph_ok && e_ok && pd_ok;

lines = { ...
    sprintf('SoC min: %.1f%% / max: %.1f%% (20..95%%) %s', ...
            min(soc), max(soc), check(soc_ok)), ...
    sprintf('P_{MGU-K} max: %.1f kW (lim 120 kW) %s', ...
            max(p_mguk)/1000, check(pk_ok)), ...
    sprintf('P_{MGU-H} max: %.1f kW (lim 50 kW) %s', ...
            max(p_mguh)/1000, check(ph_ok))};

if has_deploy
    lines{end+1} = sprintf('P_{deploy} max: %.1f kW (lim 120 kW) %s', ...
                           max(p_deploy)/1000, check(pd_ok));
    lines{end+1} = sprintf('E_{deploy}/volta max: %.2f MJ (lim 4 MJ) %s', ...
                           E_dep_max/1e6, check(e_ok));
end

lines{end+1} = sprintf('Voltas: %d  |  Tempo: %.0f s', n_voltas, T_sim);
lines{end+1} = '';
lines{end+1} = sprintf('Resultado: %s', iff(approved, 'APROVADO', 'REPROVADO'));

for i = 1:length(lines)
    text(0.05, 0.85 - (i-1)*0.08, lines{i}, ...
         'FontSize', 10, 'VerticalAlignment', 'top');
end

sgtitle('Analise dos Resultados - Co-Simulacao ERS', 'FontSize', 14);

%% =========================================================
%  RELATORIO NO CONSOLE
%  =========================================================
fprintf('\n========================================\n');
fprintf('  RELATORIO DE CO-SIMULACAO ERS\n');
fprintf('========================================\n');
fprintf('Tempo simulado:       %.0f s (%d voltas)\n', T_sim, n_voltas);
fprintf('\n--- Limites do Regulamento ---\n');
fprintf('SoC min:              %.1f%%  (>= 20%%) -> %s\n', min(soc), check(min(soc) >= SOC_MIN*100 - 0.5));
fprintf('SoC max:              %.1f%%  (<= 95%%) -> %s\n', max(soc), check(max(soc) <= SOC_MAX*100 + 0.5));
fprintf('P_mguk max:           %.1f kW (<= 120 kW) -> %s\n', max(p_mguk)/1000, check(pk_ok));
fprintf('P_mguh max:           %.1f kW (<= 50 kW)  -> %s\n', max(p_mguh)/1000, check(ph_ok));
if has_deploy
    fprintf('P_deploy max:         %.1f kW (<= 120 kW) -> %s\n', max(p_deploy)/1000, check(pd_ok));
    fprintf('E_deploy/volta max:   %.2f MJ (<= 4 MJ)  -> %s\n', E_dep_max/1e6, check(e_ok));
end
fprintf('\nResultado geral:      %s\n', iff(approved, 'APROVADO', 'REPROVADO'));
fprintf('========================================\n');

%% Funcoes auxiliares
function s = check(ok)
    if ok, s = 'OK'; else, s = 'FALHA'; end
end

function r = iff(cond, t, f)
    if cond, r = t; else, r = f; end
end
