// Autoscale test for the Public API App Service plan.
//
// Generates enough sustained CPU pressure to make the autoscale rules in
// infra/modules/publicApi.bicep fire, and records what the plan did.
//
//   k6 run -e PHASE=probe     -e BASE_URL=https://<api-host> tests/LoadTests/autoscale.js
//   k6 run -e PHASE=scale-out -e BASE_URL=https://<api-host> tests/LoadTests/autoscale.js
//   k6 run -e PHASE=full      -e BASE_URL=https://<api-host> tests/LoadTests/autoscale.js
//
// Run scripts/watch-instances.sh alongside it for the authoritative instance
// count from Azure Monitor.

import { sleep } from 'k6';
import exec from 'k6/execution';
import { Gauge, Counter } from 'k6/metrics';

import {
  AUTOSCALE,
  LOAD_VUS,
  SATURATE_MIN,
  IDLE_MIN,
  METRIC_LAG_MIN,
  BASE_URL,
  buildOptions,
} from './config.js';
import { cpuBurn, idleProbe, instanceIdOf, clearAffinity } from './lib/api.js';

export const options = buildOptions();

// Headline client-side signal. k6 reports a Gauge's max in the summary, so this
// metric's max is the most distinct App Service instances any single VU
// observed. Each VU has its own JS runtime, so it is a lower bound on the real
// instance count, never an upper one.
const instancesSeen = new Gauge('autoscale_instances_seen');

// If this stays at zero the ARRAffinity cookie is absent, instance detection is
// blind, and only the az CLI watcher can tell you what the plan did.
const affinityObserved = new Counter('autoscale_affinity_cookie_present');

// Per-VU, by k6's execution model. Do not read this from setup/teardown - they
// run in their own runtimes where it is always empty.
const seenByThisVu = new Set();

export function setup() {
  const phase = __ENV.PHASE || 'probe';
  const expectedActions = Math.ceil(
    (AUTOSCALE.maxInstances - AUTOSCALE.minInstances) / AUTOSCALE.scaleOutStep
  );

  console.log(
    [
      '',
      '─── autoscale test ────────────────────────────────',
      `  target        ${BASE_URL}`,
      `  phase         ${phase}`,
      `  load VUs      ${LOAD_VUS}`,
      '',
      `  policy        min=${AUTOSCALE.minInstances} max=${AUTOSCALE.maxInstances}`,
      `  scale out     CPU avg > ${AUTOSCALE.cpuScaleOut}% over ${AUTOSCALE.scaleOutWindowMin}m`,
      `                +${AUTOSCALE.scaleOutStep} instances, ${AUTOSCALE.scaleOutCooldownMin}m cooldown`,
      `  scale in      CPU avg < ${AUTOSCALE.cpuScaleIn}% over ${AUTOSCALE.scaleInWindowMin}m`,
      `                -${AUTOSCALE.scaleInStep} instance, ${AUTOSCALE.scaleInCooldownMin}m cooldown`,
      '',
      `  expect        ${expectedActions} scale-out action(s) to reach max`,
      `  saturate for  ${SATURATE_MIN}m  (incl. ${METRIC_LAG_MIN}m metric lag)`,
      `  idle for      ${IDLE_MIN}m  (to fall back to min)`,
      '───────────────────────────────────────────────────',
      '',
    ].join('\n')
  );

  if (phase === 'probe') {
    console.warn(
      'PHASE=probe is a harness check only - it is far shorter than the ' +
        `${AUTOSCALE.scaleOutWindowMin}m metric window, so no scale event will fire.`
    );
  }
}

export default function () {
  // Without this, App Service affinity pins each VU to the instance it first
  // hit, so instances added by a scale-out would sit idle and the test would
  // conclude that scaling did not help. See clearAffinity() for detail.
  clearAffinity();

  // The idle phase ramps the target down to 1 VU; anything above that is a load
  // generator. Keying off the active VU count means this follows the stage ramp
  // exactly, with no second clock to keep in sync.
  const idle = exec.instance.vusActive <= 1;

  const res = idle ? idleProbe() : cpuBurn();

  const instanceId = instanceIdOf(res);
  if (instanceId) {
    affinityObserved.add(1);
    seenByThisVu.add(instanceId);
    instancesSeen.add(seenByThisVu.size);
  }

  // The load driver must not be throttled - a sleep here would cap CPU below
  // the scale-out threshold. The idle probe does sleep, because its job is to
  // keep the metric stream alive at low CPU, not to create load.
  if (idle) {
    sleep(10);
  }
}

export function teardown() {
  console.log(
    '\nautoscale_instances_seen (max) above is a lower bound - affinity may have ' +
      'kept a VU on one instance. Confirm with: scripts/watch-instances.sh --history\n'
  );
}
