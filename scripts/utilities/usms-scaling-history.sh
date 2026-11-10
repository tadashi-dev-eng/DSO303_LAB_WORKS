#!/usr/bin/env bash
# Export the USMS enrolment service's complete scaling configuration and history
# as one JSON document: outputs/lab-06-scaling-history.json (Lab 10's first object).
# Read-only against AWS. Works from any directory. No hard-coded resource ID,
# policy or alarm name: everything is discovered from the service ARN downwards.
# No access key is read or referenced.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env"
source "$REPO_ROOT/configs/lab-04.env"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION_COURSE}"
OUT="$REPO_ROOT/outputs/lab-06-scaling-history.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SVC_ARN=$(aws ecs describe-services --cluster "$USMS_ECS_CLUSTER" \
  --services "$USMS_ENROLMENT_SERVICE" --query 'services[0].serviceArn' --output text)
RID="${SVC_ARN##*:}"

# Each call writes a JSON file; an unsupported call is recorded as such, not dropped.
call() {  # call <file> <aws args...>
  local f="$TMP/$1"; shift
  if ! "$@" --output json > "$f" 2> "$f.err"; then
    python3 -c 'import json,sys;print(json.dumps({"unsupported": open(sys.argv[1]).read().strip()}))' "$f.err" > "$f"
  fi
}
call target.json     aws application-autoscaling describe-scalable-targets --service-namespace ecs --resource-ids "$RID"
call policies.json   aws application-autoscaling describe-scaling-policies --service-namespace ecs --resource-id "$RID"
call scheduled.json  aws application-autoscaling describe-scheduled-actions --service-namespace ecs --resource-id "$RID"
call activities.json aws application-autoscaling describe-scaling-activities --service-namespace ecs --resource-id "$RID" --include-not-scaled-activities
call alarms.json     aws cloudwatch describe-alarms

python3 - "$TMP" "$SVC_ARN" "$RID" "$OUT" << 'PY'
import datetime, json, os, sys
tmp, svc_arn, rid, out = sys.argv[1:5]
load = lambda n: json.load(open(os.path.join(tmp, n)))
policies = load("policies.json")
pol_list = policies.get("ScalingPolicies", [])
arns = {p["PolicyARN"] for p in pol_list}
names = {a["AlarmName"] for p in pol_list for a in (p.get("Alarms") or [])}
alarms = [a for a in load("alarms.json").get("MetricAlarms", [])
          if a["AlarmName"] in names or arns.intersection(a.get("AlarmActions") or [])]
doc = {
    "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "serviceArn": svc_arn,
    "resourceId": rid,
    "scalableTarget": (load("target.json").get("ScalableTargets") or [None])[0],
    "scalingPolicies": pol_list,
    "scheduledActions": load("scheduled.json"),
    "alarms": [{k: a.get(k) for k in ("AlarmName", "AlarmArn", "Namespace", "MetricName", "Statistic",
               "Period", "EvaluationPeriods", "Threshold", "ComparisonOperator", "TreatMissingData",
               "AlarmActions", "StateValue", "StateReason", "StateUpdatedTimestamp")} for a in alarms],
    "scalingActivities": load("activities.json"),
}
json.dump(doc, open(out, "w"), indent=2, default=str)
print(f"wrote {out}: {len(pol_list)} policies, {len(alarms)} alarms")
PY
