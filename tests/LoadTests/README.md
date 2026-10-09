# Public API autoscale test (k6)

A single-purpose load test: **does the Public API's App Service plan actually
scale out under load and scale back in when the load stops?**

It is not a performance or functional test. Latency is not asserted, and
endpoint correctness is covered by `tests/PublicApiIntegrationTests`. The only
job here is to generate enough sustained pressure to make the autoscale rules
fire, and to record what the plan did.

Plain JavaScript run by [k6](https://k6.io) — no `.csproj`, and `dotnet test`
does not pick it up.

## The policy under test

From `infra/modules/publicApi.bicep`, defaults from `infra/main.bicepparam`:

| | Rule | Window | Action | Cooldown | Covered |
|---|---|---|---|---|---|
| 1 | `CpuPercentage` avg **> 70%** | 2 min | **+2** instances | 3 min | yes |
| 2 | `CpuPercentage` avg **< 30%** | 5 min | **−1** instance | 5 min | yes |
| 3 | `HttpQueueLength` avg **> 10** | 2 min | **+1** instance | 3 min | **no** — see below |

Bounds: **min 1, max 5** instances. S1 Standard plan.

Two properties of this policy drive the whole test design:

- **Autoscale targets the _plan_, not the API app.** The West EU plan hosts both
  the Public API *and* the West EU Web app (`infra/main.bicep`), and scaling out
  adds instances for both. `CpuPercentage` is averaged across the plan's
  *instances*, and both apps share each instance's CPU — so a saturated API
  raises the metric on its own; an idle Web app does not dilute it.
- **The rules still run on minutes, not seconds.** Even at a 2-minute window
  plus Azure's metric ingestion lag, nothing happens for ~4 minutes. The phase
  durations below are arithmetic, not padding.

## Install k6

```bash
winget install k6 --source winget     # Windows
brew install k6                       # macOS
```

## Run it

```bash
API=https://api-eshop-<suffix>eu.azurewebsites.net

# 1. Harness check (~3 min). Confirms the driver pegs CPU and that instance
#    detection works. Too short to trigger any rule - it will say so.
k6 run -e PHASE=probe -e BASE_URL=$API tests/LoadTests/autoscale.js

# 2. Scale-out (~13 min). Expect 1 -> 3 -> 5 instances.
k6 run -e PHASE=scale-out -e BASE_URL=$API tests/LoadTests/autoscale.js

# 3. Round trip (~38 min). Out to the ceiling, then back to the floor.
k6 run -e PHASE=full -e BASE_URL=$API tests/LoadTests/autoscale.js
```

Run the watcher in a second terminal to see the real instance count move:

```bash
tests/LoadTests/scripts/watch-instances.sh

# TIME        INSTANCES   CPU %
# ────        ─────────   ─────
# 14:02:11    1           18.4
# 14:09:11    1           82.7
# 14:10:11    3           79.1       <-- SCALED OUT (1 -> 3)
```

## Phases

| Phase | Duration | Shape | Expected outcome |
|---|---|---|---|
| `probe` | ~3 min | 25 VUs for 2 min | None — harness check only |
| `scale-out` | ~13 min | saturate for 10 min | 1 → 3 → 5 |
| `full` | ~38 min | saturate, then idle 25 min | 1 → 5 → 1 |

There is no scale-in-only phase: you cannot observe scale-in from the floor, so
it would just be `full` with a shorter preamble.

The 10 and 25 minute figures are computed in `config.js`, not hard-coded:

```
saturate = window(2) + metric lag(2) + (actions−1 = 1) × cooldown(3) + margin(3) = 10 min
idle     = window(5) + metric lag(2) + (steps−1 = 3) × cooldown(5) + margin(3) = 25 min
```

Azure's time window is a *rolling* lookback, so after a cooldown expires the
trailing window is already full of saturated samples and the next action fires
immediately — only the first action waits a full window. Change a rule in the
bicep and the `AUTOSCALE` block in `config.js`, and the phase durations follow.

## How load is generated

`POST /api/authenticate`. `PasswordSignInAsync` runs Identity's default hasher
(PBKDF2-HMAC-SHA512, 100k iterations — nothing in `src/` overrides it), which is
pure CPU on the instance. It is the only endpoint in this API that meaningfully
moves `CpuPercentage`, which is what Rules 1 and 2 measure.

Correct credentials are used deliberately — `PasswordSignInAsync` is called with
`lockoutOnFailure: true`, so driving it with bad passwords would lock the admin
account out and degrade the load into cheap 400s.

The idle phase switches to `GET /health` so the plan keeps reporting a *low* CPU
metric rather than no metric at all, which is what Rule 2 needs.

## Reading the result

The headline metric is **`autoscale_instances_seen`** — its `max` is the most
distinct App Service instances a single VU observed, read from the
`X-Instance-Id` response header that `src/PublicApi/Program.cs` sets from
`WEBSITE_INSTANCE_ID`.

Treat it as a **lower bound**. Each k6 VU has its own JS runtime, so no VU sees
the full picture, and a low value does not by itself prove autoscale failed.
`scripts/watch-instances.sh --history` reads the autoscale engine's own decision
log and is authoritative:

```bash
tests/LoadTests/scripts/watch-instances.sh --history
```

If `autoscale_affinity_cookie_present` is **0**, neither the header nor the
cookie came back, in-test instance detection is blind, and the az CLI watcher is
your only signal. Against a current deployment that usually means the API has
not been redeployed since `X-Instance-Id` was added.

`http_req_failed{kind:load}` is the one hard threshold (< 5%). A saturated API
returning slow responses is expected and fine; one returning **5xx** is not —
CPU stops being a valid signal and the autoscale verdict is meaningless.

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `BASE_URL` | `https://localhost:5099` | Trailing slash is stripped |
| `PHASE` | `probe` | See the phase table |
| `LOAD_VUS` | `25` | Concurrency during saturation — tune this (below) |
| `REQUEST_TIMEOUT` | `45s` | Per-request cap; k6's own default of 60s wastes VU time |
| `MIN_INSTANCES` / `MAX_INSTANCES` | `1` / `5` | Must match the deployed policy |
| `CPU_SCALE_OUT` / `CPU_SCALE_IN` | `70` / `30` | Must match the deployed policy |
| `METRIC_LAG_MIN` | `2` | Budget for Azure metric ingestion delay |
| `SAFETY_MARGIN_MIN` | `3` | Added to each computed phase |
| `API_USERNAME` / `API_PASSWORD` | `admin@microsoft.com` / `Pass@word1` | |

**Tuning `LOAD_VUS`:** run `PHASE=probe` and watch the CPU column in the
watcher. The plan must sit clearly above `CPU_SCALE_OUT` (70%) — remember it is
an average across the plan, including the Web app. If CPU stalls below 70%,
raise `LOAD_VUS`; if k6 itself saturates first, run it from a bigger machine or
distribute it.

The aim is to keep `MAX_INSTANCES` worth of CPU busy, **not** to maximise
concurrency. `/api/authenticate` is a slow CPU-bound call (~0.5s of CPU on an
S1 core), so a single instance saturates at roughly 2 requests/sec. Piling on
VUs past that point does not raise CPU — it is already at 100% — it just builds
a request queue. A 50-VU probe produced a 25-second median latency and requests
hitting k6's 60s timeout; 25 VUs saturates all 5 instances with headroom while
keeping latency survivable at 1 instance. Watch `http_req_duration`: if the
median approaches `REQUEST_TIMEOUT`, lower `LOAD_VUS`.

## Caveats worth knowing before you trust a run

**Rule 3 (`HttpQueueLength`) is not covered.** The only endpoint that could hold
connections open is `GET /api/catalog-items`, whose delay is
`await Task.Delay(1000)` — genuinely async, so requests are accepted and parked
rather than queued, and `HttpQueueLength` stays near zero. A driver aimed at it
would generate load without ever moving the metric, so there isn't one. In
practice Rule 3 fires as a side effect of CPU saturation.

**Redeploy the API before your first run.** Two of the fixes live in the app and
the infra, not the test: `clientAffinityEnabled: false` and the `X-Instance-Id`
header. Until the API is redeployed, instance detection falls back to the
`ARRAffinity` cookie and clients stay pinned to one instance.

**Do not deploy during a run.** `infra/main.bicep` sets the plan's `capacity` to
`apiMinInstances` on every deployment, so running `1-infra.yml` mid-test resets
the instance count underneath you. The bicep comments call this out too.

**Scale-in stays deliberately slower than scale-out.** A 5-minute window plus
5-minute cooldown means a 5 → 1 descent takes ~25 minutes. That asymmetry is
intentional — adding capacity late costs latency, removing it early costs
thrash. App Service also will not drop below the plan's deployed `capacity`.

**Cost.** `PHASE=full` holds up to 5 S1 instances for ~38 minutes. Run it
against `dev`/`staging` (`-e ENVIRONMENT=dev` for the watcher), not `prod`.

## Files

| File | Purpose |
|---|---|
| `autoscale.js` | The test: load phases, instance detection, reporting |
| `config.js` | Policy constants, computed phase durations, thresholds |
| `lib/api.js` | CPU load driver, idle probe, affinity handling |
| `scripts/watch-instances.sh` | Azure Monitor instance count + autoscale history |

## CI

k6 exits non-zero on a threshold breach, but a green run only proves the API
stayed up — the scaling verdict comes from the instance count. For a real gate,
assert on the count after the load:

```yaml
- name: Autoscale test
  run: |
    k6 run -e PHASE=scale-out -e BASE_URL=${{ env.API_URL }} \
      tests/LoadTests/autoscale.js
    count=$(tests/LoadTests/scripts/watch-instances.sh --once)
    echo "Instances after load: $count"
    [ "$count" -ge 3 ] || { echo "::error::plan did not scale out"; exit 1; }
```

Expect ~20 minutes of wall clock, so keep this on a schedule or a manual
trigger rather than on every pull request.
