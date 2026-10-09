// Configuration for the Public API autoscale test.
//
// Phase durations are derived from the real autoscale rules in
// infra/modules/publicApi.bicep. If you change a rule, change the AUTOSCALE
// block below to match - otherwise the test asserts against a policy that no
// longer exists.

// ──────────────────────────────────────────────
// The autoscale policy under test
// (infra/modules/publicApi.bicep -> Microsoft.Insights/autoscalesettings)
//
// Target: the App Service PLAN, not the API app. The West EU plan hosts both
// the Public API and the West EU Web app, so CpuPercentage is averaged across
// every instance of both apps.
//
// Rule 3 (HttpQueueLength > 10) is deliberately not covered - see the README.
//
// Windows and cooldowns here must match the bicep. They were deliberately
// shortened from PT5M/PT5M and PT10M/PT10M: this API saturates its CPU within
// seconds, so averaging over 5 minutes left users on a 12-second latency for
// 7+ minutes before a single instance was added.
// ──────────────────────────────────────────────
export const AUTOSCALE = {
  minInstances: Number(__ENV.MIN_INSTANCES || 1),
  maxInstances: Number(__ENV.MAX_INSTANCES || 5),

  // Rule 1: CpuPercentage Avg over PT2M > 70 -> +2 instances, cooldown PT3M
  cpuScaleOut: Number(__ENV.CPU_SCALE_OUT || 70),
  scaleOutWindowMin: 2,
  scaleOutCooldownMin: 3,
  scaleOutStep: 2,

  // Rule 2: CpuPercentage Avg over PT5M < 30 -> -1 instance, cooldown PT5M
  cpuScaleIn: Number(__ENV.CPU_SCALE_IN || 30),
  scaleInWindowMin: 5,
  scaleInCooldownMin: 5,
  scaleInStep: 1,
};

// Azure App Service metrics arrive at a 1-minute grain with ingestion delay, so
// a rule never fires the instant its time window is satisfied. Budget for it,
// or the test will declare "no scale-out" while the scale event is in flight.
export const METRIC_LAG_MIN = Number(__ENV.METRIC_LAG_MIN || 2);

// Extra minutes on top of each computed minimum, so a slightly slow metric
// pipeline does not turn a working policy into a test failure.
const SAFETY_MARGIN_MIN = Number(__ENV.SAFETY_MARGIN_MIN || 3);

export const BASE_URL = (__ENV.BASE_URL || 'https://localhost:5099').replace(/\/+$/, '');

// Seeded by AppIdentityDbContextSeed on every instance (the deployed API runs
// with UseOnlyInMemoryDatabase=true, so each instance seeds its own store).
export const CREDENTIALS = {
  username: __ENV.API_USERNAME || 'admin@microsoft.com',
  password: __ENV.API_PASSWORD || 'Pass@word1',
};

// Concurrency during the saturating phase. Tune until the plan's CpuPercentage
// sits comfortably above cpuScaleOut - see the README.
export const LOAD_VUS = Number(__ENV.LOAD_VUS || 25);

// Per-request timeout. k6 defaults to 60s, which is long enough that a single
// stuck request parks a VU for a full minute instead of generating CPU load.
// Must stay above the latency the API shows when saturated at minInstances - if
// it is too tight, every request fails and the run tells you nothing.
export const REQUEST_TIMEOUT = __ENV.REQUEST_TIMEOUT || '45s';

export const ENDPOINT = {
  cpuBurn: 'autoscale.cpu-burn',
  idleProbe: 'autoscale.idle-probe',
};

/**
 * Minutes of sustained pressure needed for `actions` scale actions to fire.
 *
 * The first action waits for the metric time window to fill, plus ingestion
 * lag. Each later action only waits out the cooldown: Azure's time window is a
 * rolling lookback, so by the time a cooldown expires the trailing window is
 * already full of saturated samples and the rule can fire immediately. Adding
 * a fresh window per action would overstate the duration by ~40%.
 */
function minutesFor(actions, windowMin, cooldownMin) {
  return windowMin + METRIC_LAG_MIN + (actions - 1) * cooldownMin + SAFETY_MARGIN_MIN;
}

function stepsBetweenBounds(step) {
  return Math.max(1, Math.ceil((AUTOSCALE.maxInstances - AUTOSCALE.minInstances) / step));
}

/** Sustained load needed to climb from the floor to the ceiling. */
export const SATURATE_MIN = minutesFor(
  stepsBetweenBounds(AUTOSCALE.scaleOutStep),
  AUTOSCALE.scaleOutWindowMin,
  AUTOSCALE.scaleOutCooldownMin
);

/** Idle time needed to fall from the ceiling back to the floor. */
export const IDLE_MIN = minutesFor(
  stepsBetweenBounds(AUTOSCALE.scaleInStep),
  AUTOSCALE.scaleInWindowMin,
  AUTOSCALE.scaleInCooldownMin
);

// ──────────────────────────────────────────────
// Phases.
//
// These are long on purpose. Scale-out averages CPU over a 5-minute window and
// then waits out a 5-minute cooldown; scale-in uses 10 and 10. A 2-minute test
// cannot observe a 5-minute window, so there is no short version of this that
// means anything.
// ──────────────────────────────────────────────
const PHASES = {
  // Harness check: confirms the driver pegs CPU and that instance detection
  // works. Far too short to trigger any rule.
  probe: [
    { duration: '30s', target: LOAD_VUS },
    { duration: '2m', target: LOAD_VUS },
    { duration: '30s', target: 0 },
  ],

  // Drive CPU above the threshold and hold long enough for every scale-out
  // action to fire. Expect minInstances -> maxInstances.
  'scale-out': [
    { duration: '1m', target: 1 },
    { duration: '1m', target: LOAD_VUS },
    { duration: `${SATURATE_MIN}m`, target: LOAD_VUS },
    { duration: '30s', target: 0 },
  ],

  // Round trip: out to the ceiling, then idle back down to the floor. There is
  // no scale-in-only phase because you cannot observe scale-in from the floor,
  // so it would be this phase with a shorter preamble.
  full: [
    { duration: '1m', target: 1 },
    { duration: '1m', target: LOAD_VUS },
    { duration: `${SATURATE_MIN}m`, target: LOAD_VUS },
    // Drop the load fast. A k6 stage ramps LINEARLY towards its target, so
    // going straight from LOAD_VUS to 1 over IDLE_MIN would bleed CPU off
    // gradually and only cross below cpuScaleIn near the very end - leaving no
    // room for the 10m window plus cooldowns, so scale-in would never be seen.
    { duration: '30s', target: 1 },
    // The actual observation window, held flat at idle.
    { duration: `${IDLE_MIN}m`, target: 1 },
    { duration: '30s', target: 0 },
  ],
};

export function buildOptions() {
  const phase = __ENV.PHASE || 'probe';
  const stages = PHASES[phase];

  if (!stages) {
    throw new Error(
      `Unknown PHASE "${phase}". Valid values: ${Object.keys(PHASES).join(', ')}`
    );
  }

  return {
    insecureSkipTLSVerify: true,
    stages,
    tags: { phase },
    // These phases run for tens of minutes at high RPS. Nothing here reads a
    // response body - instance detection uses the ARRAffinity cookie, which is
    // a header - so dropping bodies keeps memory flat over a long run.
    discardResponseBodies: true,
    // The point is sustained pressure, not latency, so a saturated API
    // returning slow responses is not a failure. The only hard gate is that it
    // stays up: if it is returning 5xx then CPU is not a valid signal and the
    // autoscale verdict is meaningless.
    thresholds: {
      'http_req_failed{kind:load}': ['rate<0.05'],
    },
  };
}
