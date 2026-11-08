#!/usr/bin/env bash
# Lab 05 Exercise 3 - load balancer decision-table report.
# Walks every ALB whose name starts with usms- and prints what each listener does
# with a request, in evaluation order. Also writes outputs/lab-05-lb-report.json.
# Read-only; takes no arguments; safe to run from any directory.
#
# Deliberately NOT using -e: a listener or target group that cannot be read must be
# shown as an empty section on its own line, not end the report before the next ALB.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env"
# The floci profile's own region differs from the course region on this machine.
export AWS_DEFAULT_REGION="$AWS_REGION_COURSE"
OUT="$REPO_ROOT/outputs/lab-05-lb-report.json"

summarise_action() {   # $1 = one action as JSON; prints its right-hand side
  local action="$1" type tg_arn tg_name total healthy
  type=$(jq -r '.Type' <<< "$action")
  case "$type" in
    forward)
      tg_arn=$(jq -r '.TargetGroupArn // .ForwardConfig.TargetGroups[0].TargetGroupArn // ""' <<< "$action")
      tg_name="${tg_arn#*:targetgroup/}"; tg_name="${tg_name%%/*}"
      total=$(aws elbv2 describe-target-health --target-group-arn "$tg_arn" \
                --query 'length(TargetHealthDescriptions)' --output text 2>/dev/null || echo 0)
      healthy=$(aws elbv2 describe-target-health --target-group-arn "$tg_arn" \
                --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text 2>/dev/null || echo 0)
      printf '%s (%s targets, %s healthy)' "$tg_name" "$total" "$healthy" ;;
    fixed-response) printf 'fixed-response %s' "$(jq -r '.FixedResponseConfig.StatusCode' <<< "$action")" ;;
    redirect)       printf 'redirect %s' "$(jq -r '.RedirectConfig.StatusCode' <<< "$action")" ;;
    *)              printf '%s' "$type" ;;
  esac
}

records='[]'
lbs=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?starts_with(LoadBalancerName, 'usms-')]" --output json)
[ "$(jq 'length' <<< "$lbs")" -eq 0 ] && echo "no load balancer named usms-*"

while read -r lb; do
  [ -z "$lb" ] && continue
  name=$(jq -r '.LoadBalancerName' <<< "$lb")
  arn=$(jq -r '.LoadBalancerArn' <<< "$lb")
  printf '%-20s %s  %s  %s  AZs=%s  SGs=%s\n' "$name" \
    "$(jq -r '.Scheme' <<< "$lb")" "$(jq -r '.Type' <<< "$lb")" "$(jq -r '.State.Code' <<< "$lb")" \
    "$(jq '.AvailabilityZones | length' <<< "$lb")" "$(jq '.SecurityGroups | length' <<< "$lb")"

  listeners=$(aws elbv2 describe-listeners --load-balancer-arn "$arn" --query 'Listeners' --output json 2>/dev/null || echo '[]')
  [ "$(jq 'length' <<< "$listeners")" -eq 0 ] && echo "  (no listeners)"
  lb_rows='[]'

  while read -r listener; do
    [ -z "$listener" ] && continue
    printf '  %s:%s\n' "$(jq -r '.Protocol' <<< "$listener")" "$(jq -r '.Port' <<< "$listener")"
    listener_arn=$(jq -r '.ListenerArn' <<< "$listener")

    # Priority is a string and the default rule's is the word "default". Sorting the
    # strings would put "10" before "5", so numbers sort numerically and the default
    # is given a sort key above the API's 50000 maximum to keep it last.
    rules=$(aws elbv2 describe-rules --listener-arn "$listener_arn" --output json 2>/dev/null \
              | jq -c '(.Rules // []) | sort_by(if .Priority == "default" then 99999 else (.Priority | tonumber) end) | .[]')

    while read -r rule; do
      [ -z "$rule" ] && continue
      priority=$(jq -r '.Priority' <<< "$rule")
      field=$(jq -r '.Conditions[0].Field // "-"' <<< "$rule")
      # Real AWS fills both forms; this Floci build fills only PathPatternConfig.Values.
      values=$(jq -r '(.Conditions[0] // {}) as $c
                      | (if (($c.Values // []) | length) > 0 then $c.Values
                         else ($c.PathPatternConfig.Values // []) end) | join(",")' <<< "$rule")
      [ -z "$values" ] && values="-"
      target=$(summarise_action "$(jq -c '.Actions[0]' <<< "$rule")")
      printf '    prio  %-8s %-13s %-26s -> %s\n' "$priority" "$field" "$values" "$target"
      lb_rows=$(jq --arg p "$priority" --arg f "$field" --arg v "$values" --arg t "$target" \
                   '. + [{priority:$p,field:$f,values:$v,target:$t}]' <<< "$lb_rows")
    done <<< "$rules"
  done <<< "$(jq -c '.[]' <<< "$listeners")"

  records=$(jq --arg n "$name" --argjson r "$lb_rows" '. + [{loadBalancer:$n,rules:$r}]' <<< "$records")
done <<< "$(jq -c '.[]' <<< "$lbs")"

jq . <<< "$records" > "$OUT"
