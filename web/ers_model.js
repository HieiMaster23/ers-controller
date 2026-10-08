/*
 * ers_model.js - Modelo do ERS para o painel web.
 *
 * Contem tres partes:
 *   1. Controller: emulacao ciclo a ciclo do RTL (vhdl/ers_top.vhd e
 *      cosim/hdl/ers_cosim_wrapper.vhd), com os mesmos registradores,
 *      limiares, aritmetica de ponto fixo e escala de tempo da co-simulacao
 *      (clock de 5 kHz, PWM de 100 contagens, passo de planta de 20 ms).
 *   2. Plant / RaceScenario: porta de cosim/plant.py.
 *   3. Driver: modelo simples de carro para pilotar pelo navegador.
 *
 * A fidelidade ao VHDL e verificada no CI por web/test/compare_with_vhdl.js,
 * que compara esta emulacao com a co-simulacao GHDL + cocotb.
 *
 * Funciona como <script> classico (define window.ERS) e como modulo Node.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else {
    root.ERS = api;
  }
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  // Codigos de ers_mode (vhdl/ers_fsm.vhd)
  const MODE = { STANDBY: 0, HARVESTING_K: 1, HARVESTING_H: 2, DEPLOYING: 3, FAULT: 7 };
  const MODE_NAME = {
    0: "STANDBY", 1: "HARVESTING_K", 2: "HARVESTING_H", 3: "DEPLOYING", 7: "FAULT",
  };

  // Limiares do RTL (escala dos ADCs)
  const TH = {
    BRAKE: 512,              // freio > 12.5%
    THROTTLE: 2048,          // acelerador > 50%
    TURBO: 40000,            // turbo > 40 mil rpm
    SOC_FAULT_LOW: 819,      // 20%
    SOC_FAULT_HIGH: 3890,    // 95%
    SOC_DEPLOY_MIN: 1024,    // 25%: deploy bloqueia
    SOC_DEPLOY_RESUME: 1229, // 30%: deploy libera de novo
    SOC_HARVEST_MAX: 3685,   // 90%: harvest bloqueia
    SOC_HARVEST_RESUME: 3481,// 85%: harvest libera de novo
    ENERGY_MAX: 1024000,     // 4 MJ em kJ Q8
    HARVEST_DUTY: 32768,
  };

  const TWO16 = 65536;
  const TWO40 = 2 ** 40;

  /** round() do Python 3 (metade para o par), para reproduzir a planta. */
  function pyRound(x) {
    const r = Math.round(x);
    if (Math.abs(x % 1) === 0.5 && r % 2 !== 0) return r - 1;
    return r;
  }

  const clamp = (x, lo, hi) => (x < lo ? lo : x > hi ? hi : x);

  // ==========================================================================
  // 1. Controlador (RTL emulado ciclo a ciclo)
  // ==========================================================================
  const CONTROLLER_DEFAULTS = {
    clkHz: 5000,      // clock da co-simulacao
    pwmPeriod: 99,    // PWM de 100 contagens
    kp: 1024,         // ganhos do PI em Q16
    ki: 64,
    pMaxW: 120000,
    // "Modo laboratorio": desligar reproduz o RTL antes das correcoes
    hysteresis: true, // histerese de SoC na FSM
    bumpless: true,   // pre-carga do integrador na entrada em deploy
  };

  class Controller {
    constructor(options) {
      this.o = Object.assign({}, CONTROLLER_DEFAULTS, options);
      const o = this.o;
      // energy_meter.vhd: integer(SCALE_REAL) arredonda para o mais proximo
      this.integScale = Math.round(o.pMaxW / 65535 / o.clkHz / 1000 * 256 * TWO40);
      this.accumMax = TH.ENERGY_MAX * TWO40;
      this.integMax = 65535 * TWO16;
      this.integMin = 0;
      this.pwmCounts = o.pwmPeriod + 1;
      this.reset();
    }

    reset() {
      // ers_fsm
      this.state = MODE.STANDBY;
      this.deploySocReg = false;
      this.harvestSocReg = false;
      // pi_controller
      this.iAccum = 0;
      this.outputSat = 0;
      this.enableD = false;
      // power_arbiter
      this.pwmCounter = 0;
      this.threshK = 0;
      this.threshH = 0;
      this.pwmK = 0;
      this.pwmH = 0;
      // energy_meter
      this.energyAccum = 0;
      // ers_cosim_wrapper: medidores de duty
      this.win = 0;
      this.highK = 0;
      this.highH = 0;
      this.dutyKCnt = 0;
      this.dutyHCnt = 0;
      // diagnostico (para explicar as decisoes no painel)
      this.diag = { deploySocOk: false, harvestSocOk: false, energyExceeded: false };
    }

    /** energy_used (kJ em Q8), saida do energy_meter */
    get energyUsed() {
      return Math.floor(this.energyAccum / TWO40);
    }

    /** Uma borda de subida do clock. inp: valores dos ADCs. */
    tick(inp) {
      const o = this.o;
      const { brake, throttle, soc, turbo, lapReset, pMeas } = inp;
      const st = this.state;

      // ---- Logica combinacional a partir dos registradores atuais ----
      const harvestKEn = st === MODE.HARVESTING_K;
      const harvestHEn = st === MODE.HARVESTING_H;
      const deployEn = st === MODE.DEPLOYING;
      const energyUsed = this.energyUsed;

      // FSM: histerese de SoC
      let deploySocOk, harvestSocOk;
      if (o.hysteresis) {
        deploySocOk = soc > TH.SOC_DEPLOY_MIN &&
          (this.deploySocReg || soc >= TH.SOC_DEPLOY_RESUME);
        harvestSocOk = soc < TH.SOC_HARVEST_MAX &&
          (this.harvestSocReg || soc <= TH.SOC_HARVEST_RESUME);
      } else {
        deploySocOk = soc > TH.SOC_DEPLOY_MIN;
        harvestSocOk = soc < TH.SOC_HARVEST_MAX;
      }
      const faultCond = soc < TH.SOC_FAULT_LOW || soc > TH.SOC_FAULT_HIGH;
      const deployCond = throttle > TH.THROTTLE && deploySocOk && energyUsed < TH.ENERGY_MAX;
      const hkCond = brake > TH.BRAKE && harvestSocOk;
      const hhCond = turbo > TH.TURBO && harvestSocOk;

      // FSM: proximo estado (prioridade FAULT > DEPLOY > HARVEST_K > HARVEST_H)
      let next = st;
      if (faultCond) {
        next = MODE.FAULT;
      } else {
        switch (st) {
          case MODE.STANDBY:
            if (deployCond) next = MODE.DEPLOYING;
            else if (hkCond) next = MODE.HARVESTING_K;
            else if (hhCond) next = MODE.HARVESTING_H;
            break;
          case MODE.HARVESTING_K:
            if (deployCond) next = MODE.DEPLOYING;
            else if (!hkCond) next = hhCond ? MODE.HARVESTING_H : MODE.STANDBY;
            break;
          case MODE.HARVESTING_H:
            if (deployCond) next = MODE.DEPLOYING;
            else if (hkCond) next = MODE.HARVESTING_K;
            else if (!hhCond) next = MODE.STANDBY;
            break;
          case MODE.DEPLOYING:
            if (!deployCond) {
              next = hkCond ? MODE.HARVESTING_K : hhCond ? MODE.HARVESTING_H : MODE.STANDBY;
            }
            break;
          case MODE.FAULT:
            next = MODE.STANDBY; // fault_cond = 0 aqui
            break;
          default:
            next = MODE.STANDBY;
        }
      }

      // PI: enable = deploy_en, setpoint = throttle * 16, medido = p_mguk_meas
      let nextI = this.iAccum;
      let nextOut = 0;
      if (deployEn) {
        const setpoint = throttle * 16;
        const err = setpoint - pMeas;
        let iBase = this.iAccum;
        if (o.bumpless && !this.enableD) {
          iBase = clamp(setpoint * TWO16, this.integMin, this.integMax);
        }
        nextI = clamp(iBase + err * o.ki, this.integMin, this.integMax);
        const out = Math.floor((err * o.kp + iBase) / TWO16); // shift_right
        nextOut = clamp(out, 0, 65535);
      }

      // Arbitro de potencia (combinacional)
      const energyExceeded = energyUsed >= TH.ENERGY_MAX;
      let dutyK = 0;
      let dutyH = 0;
      let dutyApplied = 0;
      if (deployEn && !energyExceeded) {
        dutyK = this.outputSat;
        dutyApplied = this.outputSat;
      } else if (harvestKEn) {
        dutyK = TH.HARVEST_DUTY;
      }
      if (harvestHEn) dutyH = TH.HARVEST_DUTY;

      // Arbitro: registradores do PWM
      const nextThreshK = Math.floor(dutyK * this.pwmCounts / TWO16);
      const nextThreshH = Math.floor(dutyH * this.pwmCounts / TWO16);
      const nextCounter = this.pwmCounter >= o.pwmPeriod ? 0 : this.pwmCounter + 1;
      const nextPwmK = this.pwmCounter < this.threshK ? 1 : 0;
      const nextPwmH = this.pwmCounter < this.threshH ? 1 : 0;

      // Medidor de energia
      let nextE = this.energyAccum;
      if (lapReset) {
        nextE = 0;
      } else if (deployEn) {
        nextE = Math.min(this.energyAccum + dutyApplied * this.integScale, this.accumMax);
      }

      // Wrapper: medidores de duty (usam o valor atual dos PWMs)
      let highK = this.highK + this.pwmK;
      let highH = this.highH + this.pwmH;
      let win = this.win;
      if (win === o.pwmPeriod) {
        this.dutyKCnt = highK;
        this.dutyHCnt = highH;
        win = 0;
        highK = 0;
        highH = 0;
      } else {
        win += 1;
      }

      // ---- Atualiza todos os registradores na mesma borda ----
      this.state = next;
      this.deploySocReg = deploySocOk;
      this.harvestSocReg = harvestSocOk;
      this.iAccum = deployEn ? nextI : this.iAccum;
      this.outputSat = nextOut;
      this.enableD = deployEn;
      this.threshK = nextThreshK;
      this.threshH = nextThreshH;
      this.pwmCounter = nextCounter;
      this.pwmK = nextPwmK;
      this.pwmH = nextPwmH;
      this.energyAccum = nextE;
      this.win = win;
      this.highK = highK;
      this.highH = highH;
      this.diag = { deploySocOk, harvestSocOk, energyExceeded };
    }
  }

  // ==========================================================================
  // 2. Planta (porta de cosim/plant.py)
  // ==========================================================================
  const PLANT_DEFAULTS = {
    vNom: 400, eBat: 4e6, soc0: 0.70, rInt: 0.05,
    kMgukTorque: 0.8, pMaxMguk: 120e3, etaMguk: 0.90,
    kTurbo: 1.5e-5, pMaxMguh: 50e3, tauMguk: 0.020,
  };

  function interp(x, xs, ys) {
    if (x <= xs[0]) return ys[0];
    if (x >= xs[xs.length - 1]) return ys[ys.length - 1];
    let i = 0;
    while (xs[i] <= x) i++; // bisect_right
    const x0 = xs[i - 1], x1 = xs[i], y0 = ys[i - 1], y1 = ys[i];
    return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
  }

  const LAP_PROFILE = {
    speed: [[0, 10, 20, 28, 32, 35, 38, 45, 55, 60],
      [3000, 15000, 18000, 18000, 8000, 5000, 5000, 8000, 15000, 3000]],
    brake: [[0, 10, 20, 28, 30, 33, 36, 40, 50, 60],
      [0, 0, 0, 0, 3500, 4095, 2000, 0, 0, 0]],
    throttle: [[0, 10, 20, 28, 30, 35, 38, 45, 55, 60],
      [2048, 3500, 4095, 4095, 0, 0, 500, 2500, 4095, 2048]],
    turbo: [[0, 10, 20, 28, 32, 36, 40, 45, 55, 60],
      [20000, 45000, 60000, 65000, 30000, 20000, 25000, 40000, 60000, 20000]],
  };

  /** Volta de referencia de 60 s (a mesma da co-simulacao). */
  class RaceScenario {
    constructor() {
      this.lapTime = 60;
    }
    at(t) {
      const tl = t % this.lapTime;
      const P = LAP_PROFILE;
      return {
        speedRpm: pyRound(interp(tl, P.speed[0], P.speed[1])),
        brakeAdc: pyRound(interp(tl, P.brake[0], P.brake[1])),
        throttleAdc: pyRound(interp(tl, P.throttle[0], P.throttle[1])),
        turboRpm: pyRound(interp(tl, P.turbo[0], P.turbo[1])),
      };
    }
  }

  class Plant {
    constructor(params) {
      this.p = Object.assign({}, PLANT_DEFAULTS, params);
      this.soc = this.p.soc0;
      this.vTerm = this.p.vNom;
      this.pDeploy = 0;
      this.pHarvK = 0;
      this.pHarvH = 0;
      this.eLapDeploy = 0;
      this.eLapHarvest = 0;
    }

    availableHarvestK(inp) {
      const brakeBar = inp.brakeAdc * 100.0 / 4095.0;
      const omega = inp.speedRpm * 2.0 * Math.PI / 60.0;
      const pElec = this.p.kMgukTorque * brakeBar * omega * this.p.etaMguk;
      return Math.min(pElec, this.p.pMaxMguk);
    }

    availableHarvestH(inp) {
      return Math.min(this.p.kTurbo * inp.turboRpm ** 2, this.p.pMaxMguh);
    }

    get socAdc() {
      return clamp(pyRound(this.soc * 4095), 0, 4095);
    }

    get pMeasAdc() {
      return clamp(pyRound(this.pDeploy / this.p.pMaxMguk * 65535), 0, 65535);
    }

    newLap() {
      this.eLapDeploy = 0;
      this.eLapHarvest = 0;
    }

    step(dt, inp, mode, dutyK, dutyH) {
      const p = this.p;
      const pCmd = mode === MODE.DEPLOYING ? dutyK * p.pMaxMguk * (this.vTerm / p.vNom) : 0.0;
      const alpha = 1.0 - Math.exp(-dt / p.tauMguk);
      this.pDeploy += (pCmd - this.pDeploy) * alpha;

      const harvestKOn = mode === MODE.HARVESTING_K && dutyK > 0.0;
      const harvestHOn = mode === MODE.HARVESTING_H && dutyH > 0.0;
      this.pHarvK = harvestKOn ? this.availableHarvestK(inp) : 0.0;
      this.pHarvH = harvestHOn ? this.availableHarvestH(inp) : 0.0;

      const pBat = this.pHarvK + this.pHarvH - this.pDeploy;
      const iBat = pBat / p.vNom;
      this.vTerm = p.vNom + p.rInt * iBat;
      this.soc = Math.min(1.0, Math.max(0.0, this.soc + pBat * dt / p.eBat));

      this.eLapDeploy += this.pDeploy * dt;
      this.eLapHarvest += (this.pHarvK + this.pHarvH) * dt;
    }
  }

  // ==========================================================================
  // 3. Piloto (modo manual): carro simplificado
  // ==========================================================================
  // Distancia de uma volta, em "rpm*s": integral da velocidade da volta de
  // referencia. Assim, pilotando como a referencia, a volta dura ~60 s.
  const LAP_DISTANCE = (() => {
    const sc = new RaceScenario();
    let d = 0;
    for (let k = 0; k < 3000; k++) d += sc.at(k * 0.02).speedRpm * 0.02;
    return d;
  })();

  const DRIVER = {
    speedMin: 3000, speedMax: 18000,  // rpm do eixo do MGU-K
    accelIce: 1100,                   // rpm/s com acelerador 100% (so motor)
    accelErs: 900,                    // rpm/s extra com 120 kW de deploy
    brakeDecel: 5200,                 // rpm/s com freio 100%
    drag: 650,                        // rpm/s de arrasto na velocidade maxima
    pedalRate: 4.0,                   // pedal vai de 0 a 100% em 0.25 s
    turboIdle: 20000, turboSpan: 45000,
    turboTauUp: 0.8, turboTauDown: 1.5,
  };

  class Driver {
    constructor() {
      this.speed = 9000;
      this.throttle = 0;   // 0..1
      this.brake = 0;      // 0..1
      this.turbo = DRIVER.turboIdle;
      this.distance = 0;
    }

    /** Avanca dt com os pedais pedidos (0..1) e a potencia de deploy atual. */
    step(dt, wantThrottle, wantBrake, pDeployW) {
      const D = DRIVER;
      const rate = D.pedalRate * dt;
      this.throttle += clamp(wantThrottle - this.throttle, -rate, rate);
      this.brake += clamp(wantBrake - this.brake, -rate, rate);

      const v = this.speed / D.speedMax;
      const accel = D.accelIce * this.throttle + D.accelErs * (pDeployW / 120e3)
        - D.brakeDecel * this.brake - D.drag * v * v;
      this.speed = clamp(this.speed + accel * dt, D.speedMin, D.speedMax);

      const target = D.turboIdle + D.turboSpan * this.throttle;
      const tau = target > this.turbo ? D.turboTauUp : D.turboTauDown;
      this.turbo += (target - this.turbo) * (1 - Math.exp(-dt / tau));

      this.distance += this.speed * dt;
    }

    inputs() {
      return {
        speedRpm: Math.round(this.speed),
        brakeAdc: Math.round(this.brake * 4095),
        throttleAdc: Math.round(this.throttle * 4095),
        turboRpm: Math.round(this.turbo),
      };
    }
  }

  // ==========================================================================
  // Simulacao: acoplamento planta <-> controlador (igual a test_ers_cosim.py)
  // ==========================================================================
  const STEP_S = 0.02;
  const TICKS_PER_STEP = 100;

  class Simulation {
    /**
     * opts.mode: "auto" (volta de referencia) ou "manual" (piloto)
     * opts.controller, opts.plant: parametros (ver *_DEFAULTS)
     */
    constructor(opts = {}) {
      this.mode = opts.mode || "auto";
      this.ctrl = new Controller(opts.controller);
      this.plant = new Plant(opts.plant);
      this.scenario = new RaceScenario();
      this.driver = new Driver();
      this.k = 0;              // passos desde o inicio
      this.autoK = 0;          // posicao na volta de referencia (em passos)
      this.lap = 1;
      this.lapStartK = 0;
      this.laps = [];          // voltas completas
      this.lastInputs = this.scenario.at(0);
      this.pedals = { throttle: 0, brake: 0 };
      this.modeChanges = 0;
      this.lastMode = MODE.STANDBY;
    }

    get t() {
      return this.k * STEP_S;
    }

    get stepsPerLap() {
      return Math.round(this.scenario.lapTime / STEP_S);
    }

    /** Alterna entre "auto" e "manual" sem reiniciar a volta. */
    setMode(mode) {
      if (mode === this.mode) return;
      const progress = this.lapProgress();
      if (mode === "manual") {
        const inp = this.lastInputs;
        this.driver.speed = inp.speedRpm;
        this.driver.turbo = inp.turboRpm;
        this.driver.throttle = inp.throttleAdc / 4095;
        this.driver.brake = inp.brakeAdc / 4095;
        this.driver.distance = progress * LAP_DISTANCE;
      } else {
        this.autoK = Math.round(progress * this.stepsPerLap) % this.stepsPerLap;
        // evita fechar a volta de novo no primeiro passo
        if (this.autoK === 0) this.autoK = 1;
      }
      this.mode = mode;
    }

    get erMode() {
      return this.ctrl.state;
    }

    /** Pedais pedidos pelo usuario no modo manual (0..1). */
    setPedals(throttle, brake) {
      this.pedals = { throttle, brake };
    }

    step() {
      const dt = STEP_S;
      let inp;
      let newLap;
      if (this.mode === "auto") {
        // Mesma conta de test_ers_cosim.py (t = k * dt), com contador proprio
        // para permitir alternar com o modo manual no meio da volta
        inp = this.scenario.at(this.autoK * dt);
        newLap = this.autoK > 0 && this.autoK % this.stepsPerLap === 0;
        this.autoK += 1;
      } else {
        inp = this.driver.inputs();
        newLap = this.driver.distance >= LAP_DISTANCE;
        if (newLap) this.driver.distance -= LAP_DISTANCE;
      }
      if (newLap) this.closeLap();

      const ctrlInp = {
        brake: inp.brakeAdc,
        throttle: inp.throttleAdc,
        soc: this.plant.socAdc,
        turbo: inp.turboRpm,
        pMeas: this.plant.pMeasAdc,
        lapReset: false,
      };
      for (let i = 0; i < TICKS_PER_STEP; i++) {
        ctrlInp.lapReset = newLap && i === 0;
        this.ctrl.tick(ctrlInp);
      }

      const mode = this.ctrl.state;
      const pwmCounts = this.ctrl.pwmCounts;
      if (mode !== this.lastMode) this.modeChanges++;
      this.lastMode = mode;
      this.plant.step(dt, inp, mode, this.ctrl.dutyKCnt / pwmCounts, this.ctrl.dutyHCnt / pwmCounts);
      if (this.mode === "manual") {
        this.driver.step(dt, this.pedals.throttle, this.pedals.brake, this.plant.pDeploy);
      }
      this.lastInputs = inp;
      this.k += 1;
    }

    closeLap() {
      this.laps.push({
        lap: this.lap,
        time: (this.k - this.lapStartK) * STEP_S,
        deployMJ: this.plant.eLapDeploy / 1e6,
        harvestMJ: this.plant.eLapHarvest / 1e6,
        socEnd: this.plant.soc,
      });
      this.lap += 1;
      this.lapStartK = this.k;
      this.plant.newLap();
    }

    /** Fracao da volta atual (0..1), para o painel. */
    lapProgress() {
      if (this.mode === "auto") {
        return (this.autoK % this.stepsPerLap) / this.stepsPerLap;
      }
      return Math.min(1, this.driver.distance / LAP_DISTANCE);
    }

    snapshot() {
      const c = this.ctrl;
      const p = this.plant;
      const inp = this.lastInputs;
      return {
        t: this.t,
        lap: this.lap,
        lapTime: (this.k - this.lapStartK) * STEP_S,
        lapProgress: this.lapProgress(),
        mode: c.state,
        throttle: inp.throttleAdc / 4095,
        brake: inp.brakeAdc / 4095,
        speedRpm: inp.speedRpm,
        turboRpm: inp.turboRpm,
        socAdc: p.socAdc,
        soc: p.soc,
        pDeployKW: p.pDeploy / 1e3,
        pHarvKKW: p.pHarvK / 1e3,
        pHarvHKW: p.pHarvH / 1e3,
        setpointKW: c.state === MODE.DEPLOYING ? inp.throttleAdc * 16 / 65535 * 120 : 0,
        dutyK: c.dutyKCnt / c.pwmCounts,
        energyVhdlMJ: c.energyUsed / 256 / 1000,
        eLapDeployMJ: p.eLapDeploy / 1e6,
        eLapHarvestMJ: p.eLapHarvest / 1e6,
        vTerm: p.vTerm,
        diag: c.diag,
      };
    }
  }

  return {
    MODE, MODE_NAME, TH, STEP_S, TICKS_PER_STEP, LAP_DISTANCE,
    Controller, Plant, RaceScenario, Driver, Simulation, pyRound,
    CONTROLLER_DEFAULTS, PLANT_DEFAULTS,
  };
});
