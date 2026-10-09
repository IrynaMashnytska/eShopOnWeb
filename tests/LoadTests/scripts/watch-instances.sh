#!/usr/bin/env bash
#
# Authoritative instance-count observer for the Public API autoscale test.
#
# k6 can only infer instance count from affinity cookies. This reads the real
# numbers from Azure Monitor: the plan's InstanceCount and CpuPercentage while
# the test runs, and the autoscale engine's own scale events afterwards.
#
#   # in one terminal, alongside the k6 run
#   tests/LoadTests/scripts/watch-instances.sh
#
#   # after the run, to see what the autoscale engine actually decided
#   tests/LoadTests/scripts/watch-instances.sh --history
#
# Requires the Azure CLI, logged in (`az login`) with reader access to the
# resource group.

set -euo pipefail

PROJECT="${PROJECT:-eshop}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
REGION_SHORT="${REGION_SHORT:-weu}"
INTERVAL="${INTERVAL:-60}"

# Names follow infra/main.bicep: rg-${projectName}-${regionShort}-${environment}
# and plan-${projectName}-${regionShort}-${environment}.
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-${PROJECT}-${REGION_SHORT}-${ENVIRONMENT}}"
PLAN_NAME="${PLAN_NAME:-plan-${PROJECT}-${REGION_SHORT}-${ENVIRONMENT}}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--history] [--once]

  (no args)   Poll InstanceCount and CpuPercentage every \${INTERVAL}s until Ctrl-C.
  --history   Print the autoscale engine's scale events from the last 2 hours.
  --once      Print the current instance count and exit.

Environment overrides:
  PROJECT=$PROJECT  ENVIRONMENT=$ENVIRONMENT  REGION_SHORT=$REGION_SHORT
  RESOURCE_GROUP=$RESOURCE_GROUP
  PLAN_NAME=$PLAN_NAME
  INTERVAL=$INTERVAL
EOF
}

require_az() {
  if ! command -v az >/dev/null 2>&1; then
    echo "error: the Azure CLI (az) is not installed or not on PATH" >&2
    exit 1
  fi
}

plan_id() {
  az appservice plan show \
    --name "$PLAN_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv
}

# Current worker count as the plan itself reports it. This is the number
# autoscale is driving, and it is what the test's pass/fail should be read from.
current_capacity() {
  az appservice plan show \
    --name "$PLAN_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query 'sku.capacity' -o tsv
}

# Plan-level CPU over the last few minutes. This is the exact metric the
# autoscale rules evaluate, averaged across every instance of every app in the
# plan - which for the West EU plan includes the Web app, not just the API.
recent_cpu() {
  local id="$1"
  az monitor metrics list \
    --resource "$id" \
    --metric CpuPercentage \
    --aggregation Average \
    --interval PT1M \
    --start-time "$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
                     || date -u -v-5M '+%Y-%m-%dT%H:%M:%SZ')" \
    --query 'value[0].timeseries[0].data[-1].average' -o tsv 2>/dev/null || echo ""
}

watch() {
  local id
  id="$(plan_id)"

  echo "plan      $PLAN_NAME"
  echo "group     $RESOURCE_GROUP"
  echo "interval  ${INTERVAL}s   (Ctrl-C to stop)"
  echo
  printf '%-10s  %-10s  %-10s\n' 'TIME' 'INSTANCES' 'CPU %'
  printf '%-10s  %-10s  %-10s\n' '────' '─────────' '─────'

  local prev=""
  while true; do
    local now capacity cpu marker
    now="$(date -u '+%H:%M:%S')"
    capacity="$(current_capacity)"
    cpu="$(recent_cpu "$id")"

    # Flag the moment the count changes - that is the scale event.
    marker=""
    if [[ -n "$prev" && "$capacity" != "$prev" ]]; then
      if (( capacity > prev )); then
        marker="  <-- SCALED OUT ($prev -> $capacity)"
      else
        marker="  <-- SCALED IN ($prev -> $capacity)"
      fi
    fi
    prev="$capacity"

    printf '%-10s  %-10s  %-10s%s\n' \
      "$now" "$capacity" "${cpu:0:5}" "$marker"

    sleep "$INTERVAL"
  done
}

# The autoscale engine logs every decision it makes, including the ones it
# declined. This is the ground truth for "did the rule fire, and why".
history() {
  echo "Autoscale events for $PLAN_NAME (last 2 hours)"
  echo

  az monitor activity-log list \
    --resource-group "$RESOURCE_GROUP" \
    --offset 2h \
    --query "[?contains(operationName.value, 'autoscale')].{
               time: eventTimestamp,
               operation: operationName.localizedValue,
               status: status.localizedValue,
               detail: properties.description
             }" \
    -o table

  echo
  echo "Current instance count: $(current_capacity)"
}

require_az

case "${1:-}" in
  -h|--help) usage ;;
  --history) history ;;
  --once)    echo "$(current_capacity)" ;;
  "")        watch ;;
  *)         echo "error: unknown argument '$1'" >&2; echo >&2; usage >&2; exit 1 ;;
esac
