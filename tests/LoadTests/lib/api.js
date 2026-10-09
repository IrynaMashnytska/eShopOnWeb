// Load driver for the autoscale test, plus instance detection.
//
// Only what is needed to move the plan's CpuPercentage metric and to observe
// the instance count. Endpoint correctness is covered by
// tests/PublicApiIntegrationTests.

import http from 'k6/http';

import { BASE_URL, CREDENTIALS, ENDPOINT, REQUEST_TIMEOUT } from '../config.js';

/**
 * CPU pressure source: POST /api/authenticate.
 *
 * SignInManager.PasswordSignInAsync verifies the password with the ASP.NET
 * Core Identity default hasher (PBKDF2-HMAC-SHA512, 100k iterations - nothing
 * in src/ overrides it), which is pure CPU work on the instance. That makes it
 * the only endpoint that moves the plan's CpuPercentage metric, which is what
 * autoscale Rules 1 and 2 trigger on.
 *
 * Correct credentials are used deliberately: PasswordSignInAsync is called with
 * lockoutOnFailure: true, so driving it with bad passwords would lock the
 * account out and turn the load into cheap 400s.
 */
export function cpuBurn() {
  return http.post(
    `${BASE_URL}/api/authenticate`,
    JSON.stringify({ username: CREDENTIALS.username, password: CREDENTIALS.password }),
    {
      headers: { 'Content-Type': 'application/json' },
      tags: { name: ENDPOINT.cpuBurn, kind: 'load' },
      timeout: REQUEST_TIMEOUT,
    }
  );
}

/**
 * Cheap request for the idle phase. Scale-in needs the plan to keep reporting a
 * low CPU metric rather than no metric at all, and it keeps instance detection
 * running while the plan scales back down.
 */
export function idleProbe() {
  return http.get(`${BASE_URL}/health`, {
    tags: { name: ENDPOINT.idleProbe, kind: 'probe' },
    timeout: REQUEST_TIMEOUT,
  });
}

/**
 * Reads the serving instance's identifier from a response.
 *
 * Primary source is the X-Instance-Id header, which PublicApi's Program.cs sets
 * from WEBSITE_INSTANCE_ID. That header exists precisely so this test does not
 * have to infer instance identity from the ARRAffinity cookie - which is gone
 * now that the API sets clientAffinityEnabled: false.
 *
 * The cookie is kept as a fallback so the test still works against an older
 * deployment that predates the header.
 *
 * Either way this only sees instances that actually served one of our requests,
 * so it is a lower bound - Azure Monitor (scripts/watch-instances.sh) is
 * authoritative.
 *
 * @returns {string|null} instance id, or null if neither signal is present.
 */
export function instanceIdOf(res) {
  const header = res.headers && (res.headers['X-Instance-Id'] || res.headers['x-instance-id']);
  if (header) {
    return header;
  }

  const cookies = res.cookies || {};
  const affinity = cookies.ARRAffinity || cookies.ARRAffinitySameSite;

  return affinity && affinity.length ? affinity[0].value : null;
}

/**
 * Drops any affinity cookie this VU picked up.
 *
 * The API now sets clientAffinityEnabled: false, so there should be no cookie
 * to clear. This stays as a safety net: if affinity is ever re-enabled, or the
 * test runs against an older deployment, a pinned VU would keep hammering one
 * instance, leaving scaled-out instances idle and making a working autoscale
 * policy look broken. Cheap insurance against a silent false negative.
 */
export function clearAffinity() {
  http.cookieJar().clear(BASE_URL);
}
