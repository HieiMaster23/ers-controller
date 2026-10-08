#!/usr/bin/env node
/*
 * Compara o modelo JS do painel (web/ers_model.js) com a co-simulacao do
 * VHDL real (GHDL + cocotb). Roda a mesma corrida de 3 voltas e confere,
 * amostra a amostra, o modo da FSM, o duty, o SoC, a potencia de deploy e a
 * energia medida pelo VHDL.
 *
 * Uso: node web/test/compare_with_vhdl.js [cosim/results/race_3_laps.csv]
 * (o CSV e gerado por: python cosim/run_cosim.py test_race_3_laps)
 */
"use strict";

const fs = require("fs");
const path = require("path");
const ERS = require("../ers_model.js");

const csvPath = process.argv[2] ||
  path.join(__dirname, "..", "..", "cosim", "results", "race_3_laps.csv");

function loadCsv(file) {
  const lines = fs.readFileSync(file, "utf8").trim().split(/\r?\n/);
  const header = lines[0].split(",");
  return lines.slice(1).map((line) => {
    const cells = line.split(",");
    const row = {};
    header.forEach((h, i) => { row[h] = cells[i]; });
    return row;
  });
}

const rows = loadCsv(csvPath);
const LOG_EVERY = 5; // test_ers_cosim.py registra 1 linha a cada 5 passos
const byStep = new Map(rows.map((r) => [Math.round(Number(r.t_s) / ERS.STEP_S) - 1, r]));
const lastStep = Math.max(...byStep.keys());

const sim = new ERS.Simulation({ mode: "auto" });
let compared = 0;
let modeMismatch = 0;
let maxSocDiff = 0;
let maxPDiff = 0;
let maxEDiff = 0;
let maxDutyDiff = 0;
const firstMismatches = [];

while (sim.k <= lastStep) {
  const k = sim.k;
  sim.step();
  if (k % LOG_EVERY !== 0 || !byStep.has(k)) continue;
  const r = byStep.get(k);
  const s = sim.snapshot();
  compared++;
  if (s.mode !== Number(r.mode_code)) {
    modeMismatch++;
    if (firstMismatches.length < 5) {
      firstMismatches.push(`t=${r.t_s}s VHDL=${r.mode} JS=${ERS.MODE_NAME[s.mode]}`);
    }
  }
  maxSocDiff = Math.max(maxSocDiff, Math.abs(s.soc * 100 - Number(r.soc_pct)));
  maxPDiff = Math.max(maxPDiff, Math.abs(s.pDeployKW - Number(r.p_deploy_kw)));
  maxEDiff = Math.max(maxEDiff, Math.abs(s.energyVhdlMJ - Number(r.e_vhdl_mj)));
  maxDutyDiff = Math.max(maxDutyDiff, Math.abs(s.dutyK - Number(r.duty_k)));
}

const agreement = 1 - modeMismatch / compared;
console.log(`Amostras comparadas: ${compared} (de ${rows.length} no CSV)`);
console.log(`Modo da FSM igual ao VHDL: ${(agreement * 100).toFixed(2)}%`);
console.log(`Maior diferenca de SoC: ${maxSocDiff.toFixed(4)} p.p.`);
console.log(`Maior diferenca de potencia de deploy: ${maxPDiff.toFixed(3)} kW`);
console.log(`Maior diferenca de energia medida: ${maxEDiff.toFixed(5)} MJ`);
console.log(`Maior diferenca de duty: ${maxDutyDiff.toFixed(3)}`);
if (firstMismatches.length) console.log("Primeiras divergencias:\n  " + firstMismatches.join("\n  "));

// Tolerancias: o CSV arredonda (SoC 3 casas, kW 2, MJ 4) e o modelo usa
// ponto flutuante na planta; a logica digital deve bater exatamente.
const failures = [];
if (compared < rows.length * 0.99) failures.push("poucas amostras comparadas");
if (agreement < 1) failures.push("modo da FSM diverge do VHDL");
if (maxSocDiff > 0.01) failures.push("SoC diverge");
if (maxPDiff > 0.05) failures.push("potencia de deploy diverge");
if (maxEDiff > 0.0005) failures.push("energia medida diverge");
if (maxDutyDiff > 0.001) failures.push("duty do PWM diverge");

if (failures.length) {
  console.error("FALHOU: " + failures.join("; "));
  process.exit(1);
}
console.log("PASSOU: o modelo do painel reproduz o VHDL na corrida de referencia");
