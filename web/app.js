/* app.js - Painel "ERS ao vivo": liga o modelo (ers_model.js) a pagina. */
(function () {
  "use strict";

  const { MODE, Simulation, STEP_S, TH } = window.ERS;
  const $ = (id) => document.getElementById(id);

  // --------------------------------------------------------------------------
  // Estado da pagina
  // --------------------------------------------------------------------------
  const HISTORY_S = 30;
  const HISTORY_N = Math.round(HISTORY_S / STEP_S);

  let sim;
  let history;
  let speed = 1;
  let paused = false;
  let lastFrame = null;
  let simDebt = 0;
  const pedals = { throttle: false, brake: false };

  function options() {
    return {
      controller: {
        hysteresis: $("optHyst").checked,
        bumpless: $("optBump").checked,
      },
      plant: { soc0: Number($("optSoc0").value) / 100 },
    };
  }

  function restart() {
    const mode = sim ? sim.mode : "auto";
    sim = new Simulation(Object.assign({ mode: "auto" }, options()));
    if (mode === "manual") sim.setMode("manual");
    history = [];
    renderLaps();
  }

  // --------------------------------------------------------------------------
  // Textos: o que o controlador decidiu e por que
  // --------------------------------------------------------------------------
  const MODE_INFO = {
    [MODE.DEPLOYING]: { name: "Deploy", code: "011", color: "--deploy" },
    [MODE.HARVESTING_K]: { name: "Recuperando na frenagem", code: "001", color: "--harv-k" },
    [MODE.HARVESTING_H]: { name: "Recuperando do turbo", code: "010", color: "--harv-h" },
    [MODE.STANDBY]: { name: "Espera", code: "000", color: "--standby" },
    [MODE.FAULT]: { name: "Falha", code: "111", color: "--fault" },
  };

  const kw = (x) => `${Math.round(x)} kW`;
  const pct = (x) => `${(x * 100).toFixed(0)}%`;

  function explain(s) {
    const d = s.diag;
    const wantsDeploy = s.throttle * 4095 > TH.THROTTLE;
    const braking = s.brake * 4095 > TH.BRAKE;
    const turboHigh = s.turboRpm > TH.TURBO;
    let main = "";
    let reason = "";

    switch (s.mode) {
      case MODE.DEPLOYING:
        main = `<strong>O MGU-K está empurrando o carro com ${kw(s.pDeployKW)}</strong> tirados da bateria, somados à potência do motor a combustão.`;
        reason = `O piloto pediu ${pct(s.throttle)} do acelerador, então o controle PI busca ${kw(s.setpointKW)} (${pct(s.throttle)} de 120 kW).`;
        break;
      case MODE.HARVESTING_K:
        main = `<strong>Na frenagem, o MGU-K vira gerador</strong> e devolve ${kw(s.pHarvKKW)} para a bateria. Sem ele, essa energia viraria calor nos discos de freio.`;
        reason = "Freio acima de 12% e bateria abaixo do limite de recarga.";
        break;
      case MODE.HARVESTING_H:
        main = `<strong>O MGU-H aproveita a rotação do turbo</strong> (${(s.turboRpm / 1000).toFixed(0)} mil rpm) e gera ${kw(s.pHarvHKW)} com a energia dos gases de escape.`;
        reason = wantsDeploy && !d.deploySocOk
          ? "O piloto quer potência, mas a bateria está baixa: o controlador prefere recarregar."
          : "Turbo acima de 40 mil rpm e sem frenagem nem pedido de potência.";
        break;
      case MODE.FAULT:
        main = "<strong>Proteção ativada:</strong> a carga da bateria saiu da faixa segura (20% a 95%). Tudo fica desligado até ela voltar.";
        reason = `SoC atual: ${(s.soc * 100).toFixed(1)}%.`;
        break;
      default:
        main = "<strong>O ERS está parado.</strong>";
        if (wantsDeploy && d.energyExceeded) {
          main = "<strong>Limite do regulamento atingido:</strong> 4 MJ de deploy nesta volta. O MGU-K só volta a empurrar na próxima volta.";
        } else if (wantsDeploy && !d.deploySocOk) {
          main = "<strong>Bateria baixa:</strong> o piloto pede potência, mas o deploy está bloqueado.";
          reason = `Com histerese, o deploy para em 25% e só volta com 30%. Agora: ${(s.soc * 100).toFixed(1)}%.`;
        } else if ((braking || turboHigh) && !d.harvestSocOk) {
          main = "<strong>Bateria cheia:</strong> a recuperação está bloqueada para proteger a bateria.";
          reason = `A recuperação para em 90% e só volta com 85%. Agora: ${(s.soc * 100).toFixed(1)}%.`;
        } else {
          reason = "Acelerador abaixo de 50%, sem frenagem e turbo abaixo de 40 mil rpm.";
        }
        if (braking && s.mode === MODE.STANDBY) {
          reason += " A energia da frenagem está virando calor nos freios.";
        }
    }
    return { main, reason };
  }

  // --------------------------------------------------------------------------
  // Desenho: carro, estado, mostradores
  // --------------------------------------------------------------------------
  const fmtTime = (t) => {
    const m = Math.floor(t / 60);
    const s = t - m * 60;
    return `${m}:${s.toFixed(1).padStart(4, "0")}`;
  };

  let flowPhase = 0;
  let lastModeShown = null;

  function renderState(s, dtReal) {
    // Cronometragem
    $("lapNo").textContent = s.lap;
    $("lapTime").textContent = fmtTime(s.lapTime);
    const last = sim.laps[sim.laps.length - 1];
    $("lastLap").textContent = last ? fmtTime(last.time) : "–";

    // Modo
    const info = MODE_INFO[s.mode] || MODE_INFO[MODE.STANDBY];
    if (s.mode !== lastModeShown) {
      $("modeName").textContent = info.name;
      $("modeCode").textContent = info.code;
      $("modePill").querySelector("i").style.background = `var(${info.color})`;
      document.querySelectorAll(".fsm .node").forEach((n) => {
        const active = Number(n.dataset.mode) === s.mode;
        n.classList.toggle("active", active);
        n.querySelector("rect").style.fill = active ? `var(${info.color})` : "";
      });
      lastModeShown = s.mode;
    }
    const ex = explain(s);
    if ($("explain").innerHTML !== ex.main) $("explain").innerHTML = ex.main;
    $("reason").textContent = ex.reason;

    // Carro: fluxos de energia
    const deploying = s.pDeployKW > 1;
    const kOn = s.pHarvKKW > 0.5;
    const hOn = s.pHarvHKW > 0.5;
    const flowK = $("flowK");
    flowK.classList.toggle("active", deploying || kOn);
    flowK.classList.toggle("deploy", deploying && !kOn);
    flowK.classList.toggle("k", kOn);
    $("flowH").classList.toggle("active", hOn);
    flowPhase = (flowPhase + dtReal * 60) % 16;
    // Recuperacao: pontos andam da maquina para a bateria; deploy: o contrario
    flowK.style.strokeDashoffset = deploying && !kOn ? flowPhase : -flowPhase;
    $("flowH").style.strokeDashoffset = -flowPhase;
    $("compK").setAttribute("class", "comp" + (kOn ? " on-k" : deploying ? " on-deploy" : ""));
    $("compH").setAttribute("class", "comp" + (hOn ? " on-h" : ""));
    $("labK").textContent = deploying ? `${Math.round(s.pDeployKW)} kW →` : kOn ? `← ${Math.round(s.pHarvKKW)} kW` : "0 kW";
    $("labH").textContent = hOn ? `${Math.round(s.pHarvHKW)} kW` : "turbo";
    const heat = s.brake > 0.12 && !kOn ? Math.min(0.55, s.brake * 0.6) : 0;
    $("heatF1").style.opacity = heat;
    $("heatF2").style.opacity = heat;
    $("batFill").setAttribute("width", (146 * s.soc).toFixed(1));
    $("labBat").textContent = `${(s.soc * 100).toFixed(1)}%`;

    // Mostradores
    $("socVal").textContent = `${(s.soc * 100).toFixed(1)}%`;
    $("socFill").style.width = `${(s.soc * 100).toFixed(2)}%`;
    $("eVal").textContent = `${s.energyVhdlMJ.toFixed(2)} / 4 MJ`;
    $("eFill").style.width = `${Math.min(100, s.energyVhdlMJ / 4 * 100).toFixed(2)}%`;
    $("rDeploy").innerHTML = `${Math.round(s.pDeployKW)}<em>kW</em>`;
    $("rK").innerHTML = `${Math.round(s.pHarvKKW)}<em>kW</em>`;
    $("rH").innerHTML = `${Math.round(s.pHarvHKW)}<em>kW</em>`;
    // 18000 rpm no eixo do MGU-K ~ 330 km/h (escala ilustrativa)
    $("rSpeed").innerHTML = `${Math.round(s.speedRpm / 18000 * 330)}<em>km/h</em>`;
    $("rTurbo").innerHTML = `${(s.turboRpm / 1000).toFixed(0)}<em>mil rpm</em>`;
    $("rPedals").innerHTML = `${Math.round(s.throttle * 100)} · ${Math.round(s.brake * 100)}<em>%</em>`;
    $("lvlThrottle").style.height = `${(s.throttle * 100).toFixed(0)}%`;
    $("lvlBrake").style.height = `${(s.brake * 100).toFixed(0)}%`;
  }

  function renderLaps() {
    const rows = sim.laps.slice(-6).reverse().map((l) =>
      `<tr><td>${l.lap}</td><td>${fmtTime(l.time)}</td><td>${l.deployMJ.toFixed(2)} MJ</td>` +
      `<td>${l.harvestMJ.toFixed(2)} MJ</td><td>${(l.socEnd * 100).toFixed(1)}%</td></tr>`);
    const s = sim.snapshot();
    rows.unshift(`<tr class="current"><td>${s.lap} (atual)</td><td>${fmtTime(s.lapTime)}</td>` +
      `<td>${s.eLapDeployMJ.toFixed(2)} MJ</td><td>${s.eLapHarvestMJ.toFixed(2)} MJ</td>` +
      `<td>${(s.soc * 100).toFixed(1)}%</td></tr>`);
    $("lapRows").innerHTML = rows.join("");
  }

  // --------------------------------------------------------------------------
  // Graficos (canvas, janela deslizante de 30 s)
  // --------------------------------------------------------------------------
  function cssVar(name) {
    return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  }

  function setupCanvas(canvas) {
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
    }
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return { ctx, w, h };
  }

  const PAD = { l: 38, r: 10, t: 18, b: 22 };

  function drawAxes(ctx, w, h, yMax, yTicks, unit, refLines) {
    const ink3 = cssVar("--ink-3");
    const line = cssVar("--line");
    ctx.clearRect(0, 0, w, h);
    ctx.font = `11px ${cssVar("--font-data") || "monospace"}`;
    ctx.fillStyle = ink3;
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";
    const ph = h - PAD.t - PAD.b;
    for (const v of yTicks) {
      const y = PAD.t + ph * (1 - v / yMax);
      ctx.strokeStyle = line;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(PAD.l, Math.round(y) + 0.5);
      ctx.lineTo(w - PAD.r, Math.round(y) + 0.5);
      ctx.stroke();
      ctx.fillText(`${v}`, PAD.l - 6, y);
    }
    if (refLines) {
      ctx.setLineDash([3, 4]);
      ctx.strokeStyle = ink3;
      for (const v of refLines) {
        const y = PAD.t + ph * (1 - v / yMax);
        ctx.beginPath();
        ctx.moveTo(PAD.l, Math.round(y) + 0.5);
        ctx.lineTo(w - PAD.r, Math.round(y) + 0.5);
        ctx.stroke();
      }
      ctx.setLineDash([]);
    }
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    const pw = w - PAD.l - PAD.r;
    for (let s = 0; s <= HISTORY_S; s += 10) {
      const x = PAD.l + pw * (s / HISTORY_S);
      ctx.fillText(s === HISTORY_S ? "agora" : `−${HISTORY_S - s} s`, x, h - PAD.b + 6);
    }
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.fillText(unit, 2, 0);
  }

  function drawSeries(ctx, w, h, yMax, key, color) {
    const n = history.length;
    if (n < 2) return;
    const pw = w - PAD.l - PAD.r;
    const ph = h - PAD.t - PAD.b;
    const x0 = PAD.l + pw * (1 - (n - 1) / (HISTORY_N - 1));
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.lineJoin = "round";
    ctx.beginPath();
    for (let i = 0; i < n; i++) {
      const x = x0 + pw * (i / (HISTORY_N - 1));
      const y = PAD.t + ph * (1 - Math.min(history[i][key], yMax) / yMax);
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.stroke();
    // ponto final em destaque
    const yEnd = PAD.t + ph * (1 - Math.min(history[n - 1][key], yMax) / yMax);
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(PAD.l + pw, yEnd, 3.5, 0, Math.PI * 2);
    ctx.fill();
  }

  const hover = { P: null, S: null };

  function drawCrosshair(ctx, w, h, which) {
    const fx = hover[which];
    if (fx === null || history.length < 2) return null;
    const pw = w - PAD.l - PAD.r;
    const n = history.length;
    const x0 = PAD.l + pw * (1 - (n - 1) / (HISTORY_N - 1));
    const i = Math.round((fx - x0) / pw * (HISTORY_N - 1));
    if (i < 0 || i >= n) return null;
    const x = x0 + pw * (i / (HISTORY_N - 1));
    ctx.strokeStyle = cssVar("--ink-3");
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(Math.round(x) + 0.5, PAD.t);
    ctx.lineTo(Math.round(x) + 0.5, h - PAD.b);
    ctx.stroke();
    return { i, x };
  }

  function showTip(tipEl, canvas, x, html) {
    tipEl.hidden = false;
    tipEl.innerHTML = html;
    const box = canvas.clientWidth;
    const tw = tipEl.offsetWidth;
    let left = x + 12;
    if (left + tw > box) left = x - tw - 12;
    tipEl.style.left = `${Math.max(0, left)}px`;
    tipEl.style.top = "6px";
  }

  function drawCharts() {
    const cP = $("chartP");
    const a = setupCanvas(cP);
    drawAxes(a.ctx, a.w, a.h, 125, [0, 40, 80, 120], "kW", [120]);
    drawSeries(a.ctx, a.w, a.h, 125, "h", cssVar("--harv-h"));
    drawSeries(a.ctx, a.w, a.h, 125, "k", cssVar("--harv-k"));
    drawSeries(a.ctx, a.w, a.h, 125, "d", cssVar("--deploy"));
    const hp = drawCrosshair(a.ctx, a.w, a.h, "P");
    if (hp) {
      const r = history[hp.i];
      const ago = ((history.length - 1 - hp.i) * STEP_S).toFixed(1);
      showTip($("tipP"), cP, hp.x,
        `−${ago} s<br>Deploy ${r.d.toFixed(0)} kW<br>MGU-K ${r.k.toFixed(0)} kW<br>MGU-H ${r.h.toFixed(0)} kW`);
    } else {
      $("tipP").hidden = true;
    }

    const cS = $("chartS");
    const b = setupCanvas(cS);
    drawAxes(b.ctx, b.w, b.h, 100, [0, 20, 50, 80, 100], "%", [25, 30, 85, 90]);
    drawSeries(b.ctx, b.w, b.h, 100, "soc", cssVar("--ink"));
    const hs = drawCrosshair(b.ctx, b.w, b.h, "S");
    if (hs) {
      const r = history[hs.i];
      const ago = ((history.length - 1 - hs.i) * STEP_S).toFixed(1);
      showTip($("tipS"), cS, hs.x, `−${ago} s<br>SoC ${r.soc.toFixed(1)}%`);
    } else {
      $("tipS").hidden = true;
    }
  }

  function bindHover(canvasId, which) {
    const c = $(canvasId);
    c.addEventListener("pointermove", (e) => {
      hover[which] = e.clientX - c.getBoundingClientRect().left;
    });
    c.addEventListener("pointerleave", () => { hover[which] = null; });
  }

  // --------------------------------------------------------------------------
  // Laco principal
  // --------------------------------------------------------------------------
  let lapsShown = 0;
  let frameCount = 0;

  function frame(now) {
    const dtReal = lastFrame === null ? 0 : Math.min(0.1, (now - lastFrame) / 1000);
    lastFrame = now;
    if (!paused) {
      if (sim.mode === "manual") {
        sim.setPedals(pedals.throttle ? 1 : 0, pedals.brake ? 1 : 0);
      }
      simDebt += dtReal * speed;
      let steps = 0;
      while (simDebt >= STEP_S && steps < 40) {
        sim.step();
        const s = sim.snapshot();
        history.push({ d: s.pDeployKW, k: s.pHarvKKW, h: s.pHarvHKW, soc: s.soc * 100 });
        if (history.length > HISTORY_N) history.shift();
        simDebt -= STEP_S;
        steps++;
      }
      if (steps === 40) simDebt = 0;
    }
    const s = sim.snapshot();
    renderState(s, paused ? 0 : dtReal * speed);
    drawCharts();
    frameCount++;
    if (sim.laps.length !== lapsShown || frameCount % 15 === 0) {
      renderLaps();
      lapsShown = sim.laps.length;
    }
    requestAnimationFrame(frame);
  }

  // --------------------------------------------------------------------------
  // Controles
  // --------------------------------------------------------------------------
  function setMode(mode) {
    sim.setMode(mode);
    $("modeAuto").setAttribute("aria-pressed", String(mode === "auto"));
    $("modeManual").setAttribute("aria-pressed", String(mode === "manual"));
    $("pilotHint").textContent = mode === "auto"
      ? "Na volta de referência o carro segue o mesmo perfil usado nos testes do VHDL. Aperte Acelerar ou Frear para assumir o volante."
      : "Segure Acelerar para ganhar velocidade e Frear para recuperar energia. Com deploy, o carro acelera mais e a volta fica mais rápida.";
  }

  function setPedal(which, on) {
    if (on && sim.mode !== "manual") setMode("manual");
    pedals[which] = on;
    $(which === "throttle" ? "btnThrottle" : "btnBrake").setAttribute("aria-pressed", String(on));
  }

  function bindPedal(btnId, which) {
    const b = $(btnId);
    b.addEventListener("pointerdown", (e) => {
      b.setPointerCapture(e.pointerId);
      setPedal(which, true);
    });
    const up = () => setPedal(which, false);
    b.addEventListener("pointerup", up);
    b.addEventListener("pointercancel", up);
    b.addEventListener("lostpointercapture", up);
    b.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); setPedal(which, true); }
    });
    b.addEventListener("keyup", (e) => {
      if (e.key === "Enter") setPedal(which, false);
    });
  }

  const KEYS = {
    ArrowUp: "throttle", w: "throttle", W: "throttle",
    ArrowDown: "brake", s: "brake", S: "brake", " ": "brake",
  };

  function bindControls() {
    bindPedal("btnThrottle", "throttle");
    bindPedal("btnBrake", "brake");
    window.addEventListener("keydown", (e) => {
      const which = KEYS[e.key];
      if (!which || e.target.closest("input")) return;
      e.preventDefault();
      if (!e.repeat) setPedal(which, true);
    });
    window.addEventListener("keyup", (e) => {
      const which = KEYS[e.key];
      if (which) setPedal(which, false);
    });
    window.addEventListener("blur", () => {
      setPedal("throttle", false);
      setPedal("brake", false);
    });

    $("modeAuto").addEventListener("click", () => setMode("auto"));
    $("modeManual").addEventListener("click", () => setMode("manual"));
    document.querySelectorAll("[data-speed]").forEach((b) => {
      b.addEventListener("click", () => {
        speed = Number(b.dataset.speed);
        document.querySelectorAll("[data-speed]").forEach((o) =>
          o.setAttribute("aria-pressed", String(o === b)));
      });
    });
    $("btnPause").addEventListener("click", () => {
      paused = !paused;
      $("btnPause").textContent = paused ? "Continuar" : "Pausar";
    });
    $("btnRestart").addEventListener("click", restart);
    ["optHyst", "optBump"].forEach((id) => $(id).addEventListener("change", restart));
    $("optSoc0").addEventListener("input", () => {
      $("soc0Val").textContent = `${$("optSoc0").value}%`;
    });
    $("optSoc0").addEventListener("change", restart);
    document.addEventListener("visibilitychange", () => { lastFrame = null; });

    bindHover("chartP", "P");
    bindHover("chartS", "S");
  }

  // --------------------------------------------------------------------------
  // Inicio: comeca rodando a volta de referencia (com alguns segundos ja
  // simulados, para os graficos abrirem com conteudo)
  // --------------------------------------------------------------------------
  restart();
  for (let i = 0; i < Math.round(12 / STEP_S); i++) {
    sim.step();
    const s = sim.snapshot();
    history.push({ d: s.pDeployKW, k: s.pHarvKKW, h: s.pHarvHKW, soc: s.soc * 100 });
  }
  bindControls();
  renderLaps();
  requestAnimationFrame(frame);
})();
