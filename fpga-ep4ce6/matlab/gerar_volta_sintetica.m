% gerar_volta_sintetica.m
% Gera volta sintetica EXEMPLO (nao e um circuito real) para o prototipo ERS EP4CE6.
% Compativel com MATLAB e Octave (sem toolboxes extras).
%
% Empacotamento da palavra 32 bits (hex no MIF):
%   bits [7:0]   = speed     (0..255, tipico 80..250)
%   bits [15:8]  = throttle  (0..255)
%   bits [23:16] = brake     (0..255)
%   bits [27:24] = sector    (1..4)
%   bits [31:28] = 0
%
% N=900, Ts=0.1 s => 90 s de volta.

clear; close all;

N  = 900;
Ts = 0.1;
t  = (0:N-1)' * Ts;

speed    = zeros(N,1);
throttle = zeros(N,1);
brake    = zeros(N,1);
sector   = zeros(N,1);

% Segmentos do EXEMPLO (indices 1-based):
% 1-150   S1 reta longa
% 151-200 S1 freada forte
% 201-280 S1 curva media
% 281-420 S2 reta
% 421-470 S2 freada
% 471-560 S2 curva
% 561-720 S3 reta longa
% 721-770 S3 freada
% 771-850 S3/S4 curva
% 851-900 S4 reta curta ate linha

for i = 1:N
  if i <= 150
    sector(i) = 1;
    throttle(i) = 240;
    brake(i)    = 5;
    speed(i)    = 180 + round(70 * (i-1)/149);          % 180->250
  elseif i <= 200
    sector(i) = 1;
    throttle(i) = 20;
    brake(i)    = 220;
    speed(i)    = 250 - round(130 * (i-151)/49);        % 250->120
  elseif i <= 280
    sector(i) = 1;
    throttle(i) = 90;
    brake(i)    = 40;
    speed(i)    = 120 - round(20 * (i-201)/79);         % 120->100
  elseif i <= 420
    sector(i) = 2;
    throttle(i) = 235;
    brake(i)    = 8;
    speed(i)    = 100 + round(140 * (i-281)/139);       % 100->240
  elseif i <= 470
    sector(i) = 2;
    throttle(i) = 15;
    brake(i)    = 230;
    speed(i)    = 240 - round(140 * (i-421)/49);        % 240->100
  elseif i <= 560
    sector(i) = 2;
    throttle(i) = 100;
    brake(i)    = 50;
    speed(i)    = 100 + round(15 * (i-471)/89);         % 100->115
  elseif i <= 720
    sector(i) = 3;
    throttle(i) = 245;
    brake(i)    = 5;
    speed(i)    = 115 + round(135 * (i-561)/159);       % 115->250
  elseif i <= 770
    sector(i) = 3;
    throttle(i) = 10;
    brake(i)    = 240;
    speed(i)    = 250 - round(150 * (i-721)/49);        % 250->100
  elseif i <= 850
    sector(i) = 4;
    throttle(i) = 85;
    brake(i)    = 55;
    speed(i)    = 100 - round(20 * (i-771)/79);         % 100->80
  else
    sector(i) = 4;
    throttle(i) = 200;
    brake(i)    = 10;
    speed(i)    = 80 + round(70 * (i-851)/49);          % 80->150
  end
end

% Clamp
speed    = max(0, min(255, round(speed)));
throttle = max(0, min(255, round(throttle)));
brake    = max(0, min(255, round(brake)));
sector   = max(1, min(15, round(sector)));

words = bitshift(sector, 24) + bitshift(brake, 16) + bitshift(throttle, 8) + speed;

% --- MIF ---
fid = fopen('volta_sintetica.mif', 'w');
fprintf(fid, '-- Volta sintetica EXEMPLO para ERS EP4CE6\n');
fprintf(fid, '-- Pack: [31:28]=0 [27:24]=sector [23:16]=brake [15:8]=throttle [7:0]=speed\n');
fprintf(fid, 'DEPTH = 900;\n');
fprintf(fid, 'WIDTH = 32;\n');
fprintf(fid, 'ADDRESS_RADIX = DEC;\n');
fprintf(fid, 'DATA_RADIX = HEX;\n');
fprintf(fid, 'CONTENT\n');
fprintf(fid, 'BEGIN\n');
for i = 1:N
  fprintf(fid, '%4d : %08X;\n', i-1, words(i));
end
fprintf(fid, 'END;\n');
fclose(fid);

% --- CSV ---
fid = fopen('volta_sintetica.csv', 'w');
fprintf(fid, 'idx,t_s,speed,throttle,brake,sector,word_hex\n');
for i = 1:N
  fprintf(fid, '%d,%.1f,%d,%d,%d,%d,%08X\n', ...
    i-1, t(i), speed(i), throttle(i), brake(i), sector(i), words(i));
end
fclose(fid);

fprintf('Gerado: volta_sintetica.mif e volta_sintetica.csv (%d amostras)\n', N);
