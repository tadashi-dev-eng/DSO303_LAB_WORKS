#!/usr/bin/env bash
# USMS scaling report - prints the decision table of every ECS scalable target
# whose resource ID names a cluster beginning "usms-", with a computed verdict.
# Read-only. No arguments. Also writes outputs/lab-06-scaling-report.json.
#
# -e is deliberately NOT set: several calls (describe-scheduled-actions,
# describe-scaling-activities) are unimplemented on some emulator builds, and one
# unsupported read must not stop the report for the other rows. Every call that may
# fail is handled explicitly instead. -u and pipefail still catch typos and broken pipes.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION_COURSE}"
OUT_JSON="$REPO_ROOT/outputs/lab-06-scaling-report.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Level 1: every scalable target in the ecs namespace (filtered to usms- clusters in python).
aws application-autoscaling describe-scalable-targets --service-namespace ecs \
  --output json > "$TMP/targets.json" 2>/dev/null || echo '{"ScalableTargets":[]}' > "$TMP/targets.json"

python3 - "$TMP/targets.json" > "$TMP/rids.txt" << 'PY'
import json, sys
for t in json.load(open(sys.argv[1])).get("ScalableTargets", []):
    parts = t["ResourceId"].split("/")
    if len(parts) == 3 and parts[0] == "service" and parts[1].startswith("usms-"):
        print(t["ResourceId"])
PY

n=0
while read -r rid; do
  [ -n "$rid" ] || continue
  n=$((n+1))
  cluster=$(printf '%s' "$rid" | cut -d/ -f2)
  service=$(printf '%s' "$rid" | cut -d/ -f3)
  d="$TMP/$n"; mkdir -p "$d"
  printf '%s' "$rid" > "$d/rid"

  # Level 2: policies. Level 3: scheduled actions. Plus the activities and the ECS service.
  aws application-autoscaling describe-scaling-policies --service-namespace ecs \
    --resource-id "$rid" --output json > "$d/policies.json" 2>/dev/null \
    || echo '{"ScalingPolicies":[]}' > "$d/policies.json"
  aws application-autoscaling describe-scheduled-actions --service-namespace ecs \
    --resource-id "$rid" --output json > "$d/scheduled.json" 2>/dev/null \
    || echo '{"unsupported":true}' > "$d/scheduled.json"
  aws application-autoscaling describe-scaling-activities --service-namespace ecs \
    --resource-id "$rid" --max-items 1 --output json > "$d/activities.json" 2>/dev/null \
    || echo '{"unsupported":true}' > "$d/activities.json"
  aws ecs describe-services --cluster "$cluster" --services "$service" \
    --output json > "$d/service.json" 2>/dev/null || echo '{"services":[]}' > "$d/service.json"

  # Level 4: every alarm the policies name, plus every alarm whose actions name a policy - one batched call.
  python3 - "$d/policies.json" > "$d/alarm-names.txt" << 'PY'
import json, sys
names = []
for p in json.load(open(sys.argv[1])).get("ScalingPolicies", []):
    names += [a["AlarmName"] for a in p.get("Alarms") or []]
print(" ".join(dict.fromkeys(names)))
PY
  # shellcheck disable=SC2046
  if [ -s "$d/alarm-names.txt" ] && [ -n "$(tr -d ' \n' < "$d/alarm-names.txt")" ]; then
    aws cloudwatch describe-alarms --alarm-names $(cat "$d/alarm-names.txt") \
      --output json > "$d/alarms.json" 2>/dev/null || echo '{"MetricAlarms":[]}' > "$d/alarms.json"
  else
    echo '{"MetricAlarms":[]}' > "$d/alarms.json"
  fi
  # Step policies on some builds do not list their alarm; find alarms whose actions name a policy ARN.
  aws cloudwatch describe-alarms --output json > "$d/all-alarms.json" 2>/dev/null \
    || echo '{"MetricAlarms":[]}' > "$d/all-alarms.json"
done < "$TMP/rids.txt"

python3 - "$TMP" "$TMP/targets.json" "$OUT_JSON" << 'PY'
import json, os, sys
tmp, targets_file, out_json = sys.argv[1], sys.argv[2], sys.argv[3]
targets = {t["ResourceId"]: t for t in json.load(open(targets_file)).get("ScalableTargets", [])}

def num(v):
    return ("%g" % v) if isinstance(v, (int, float)) else str(v)

report = []
dirs = sorted((x for x in os.listdir(tmp) if x.isdigit()), key=int)
if not dirs:
    print("no usms- scalable targets found in the ecs namespace")
for x in dirs:
    d = os.path.join(tmp, x)
    rid = open(os.path.join(d, "rid")).read()
    t = targets[rid]
    pol = json.load(open(os.path.join(d, "policies.json"))).get("ScalingPolicies", [])
    sch = json.load(open(os.path.join(d, "scheduled.json")))
    act = json.load(open(os.path.join(d, "activities.json")))
    svcs = json.load(open(os.path.join(d, "service.json"))).get("services", [])
    alarms = {a["AlarmName"]: a for a in json.load(open(os.path.join(d, "alarms.json"))).get("MetricAlarms", [])}
    all_alarms = json.load(open(os.path.join(d, "all-alarms.json"))).get("MetricAlarms", [])
    svc = svcs[0] if svcs else {}
    mn, mx = t.get("MinCapacity"), t.get("MaxCapacity")
    desired, running = svc.get("desiredCount"), svc.get("runningCount")
    susp = t.get("SuspendedState") or {}
    on = [k.replace("Suspended", "") for k, v in susp.items() if v]

    # Verdict, evaluated top to bottom. PINNED first: if min == max nothing can move,
    # so every other verdict is irrelevant. FROZEN outranks AT-CEILING because a suspended
    # target at its ceiling cannot scale IN either, and the switch is the hidden hazard
    # an operator must see first; AT-CEILING is visible from the numbers alone.
    if mn == mx:
        verdict = "PINNED"
    elif on:
        verdict = "FROZEN"
    elif desired == mx:
        verdict = "AT-CEILING"
    elif desired == mn and len(pol) > 1:
        verdict = "AT-FLOOR"
    else:
        verdict = "ELASTIC"

    print(f"{rid}   {t.get('ScalableDimension')}")
    print(f"  bounds       min={mn}  max={mx}   desired={desired}   running={running}   {verdict}")
    print(f"  suspended    {', '.join(on) if on else 'none'}")
    short = {"ECSServiceAverageCPUUtilization": "CPU", "ECSServiceAverageMemoryUtilization": "Mem",
             "ALBRequestCountPerTarget": "ALBReq"}
    rows = []
    for p in sorted(pol, key=lambda p: (p["PolicyType"] != "TargetTrackingScaling", p["PolicyName"])):
        name = p["PolicyName"]
        if p["PolicyType"] == "TargetTrackingScaling":
            c = p.get("TargetTrackingScalingPolicyConfiguration", {})
            m = (c.get("PredefinedMetricSpecification") or {}).get("PredefinedMetricType", "custom")
            extra = "  scale-in disabled" if c.get("DisableScaleIn") else ""
            print(f"  target-track {name:<42}{short.get(m, m) + '/' + num(c.get('TargetValue')):<16}"
                  f"out={c.get('ScaleOutCooldown')}  in={c.get('ScaleInCooldown')}{extra}")
            names = [a["AlarmName"] for a in p.get("Alarms") or []]
            if names:
                states = []
                for n in names:
                    kind = "AlarmHigh" if "AlarmHigh" in n else "AlarmLow" if "AlarmLow" in n else n
                    states.append(f"{kind}={alarms.get(n, {}).get('StateValue', 'missing')}")
                print(f"                 alarms  {'  '.join(states)}")
            else:
                print("                 alarms  none listed by this build")
        else:
            c = p.get("StepScalingPolicyConfiguration", {})
            adj = " / ".join("%+d" % s["ScalingAdjustment"] for s in c.get("StepAdjustments", []))
            print(f"  step         {name:<42}{adj:<16}cooldown={c.get('Cooldown')}")
            arn = p.get("PolicyARN")
            drivers = [a for a in all_alarms if arn in (a.get("AlarmActions") or [])]
            for a in drivers:
                op = {"GreaterThanOrEqualToThreshold": ">=", "GreaterThanThreshold": ">",
                      "LessThanThreshold": "<", "LessThanOrEqualToThreshold": "<="}.get(a["ComparisonOperator"], a["ComparisonOperator"])
                print(f"                 alarm   {a['AlarmName']} = {a['StateValue']}  "
                      f"({a.get('Namespace')} {a.get('MetricName')} {op} {num(a.get('Threshold'))})")
            if not drivers:
                print("                 alarm   none - this policy can never fire")
        rows.append(p)
    if not pol:
        print("  policies     none - this target enforces its bounds and nothing else")
    if sch.get("unsupported"):
        print("  scheduled    describe-scheduled-actions not available on this build")
    else:
        acts = sch.get("ScheduledActions", [])
        for a in acts:
            print(f"  scheduled    {a['ScheduledActionName']:<34}{a.get('Schedule')}  "
                  f"{a.get('Timezone') or 'UTC'}  min={a.get('ScalableTargetAction', {}).get('MinCapacity')}")
        if not acts:
            print("  scheduled    none")
    if act.get("unsupported"):
        print("  last activity  describe-scaling-activities not available on this build")
    else:
        a = act.get("ScalingActivities", [])
        print(f"  last activity  {a[0]['StartTime']} {a[0]['StatusCode']} {a[0].get('Cause', '')}" if a else "  last activity  none recorded")
    report.append({"resourceId": rid, "verdict": verdict, "target": t, "policies": pol,
                   "scheduledActions": None if sch.get("unsupported") else sch.get("ScheduledActions", []),
                   "desiredCount": desired, "runningCount": running})
os.makedirs(os.path.dirname(out_json), exist_ok=True)
json.dump(report, open(out_json, "w"), indent=2, default=str)
PY
