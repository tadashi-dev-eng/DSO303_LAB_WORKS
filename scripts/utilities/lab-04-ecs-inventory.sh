#!/usr/bin/env bash
# Lab 04 Exercise 3 - ECS configuration drift report.
# Prints one line per service in the course cluster and writes the same data
# to outputs/lab-04-ecs-inventory.json. Read-only; safe to run from anywhere.
#
# Deliberately NOT using -e: one service that cannot be described, or a task
# definition that has been removed, must be reported as UNKNOWN on its own line
# rather than silently ending the report before the remaining services.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env"
source "$REPO_ROOT/configs/lab-04.env"

OUT="$REPO_ROOT/outputs/lab-04-ecs-inventory.json"
records='[]'

for arn in $(aws ecs list-services --cluster "$USMS_ECS_CLUSTER" \
               --query 'serviceArns[]' --output text); do
  svc=$(aws ecs describe-services --cluster "$USMS_ECS_CLUSTER" --services "$arn" \
          --query 'services[0]' --output json)

  name=$(jq -r '.serviceName // "UNKNOWN"' <<< "$svc")
  desired=$(jq -r '.desiredCount // "UNKNOWN"' <<< "$svc")
  running=$(jq -r '.runningCount // "UNKNOWN"' <<< "$svc")
  td_ref=$(jq -r '.taskDefinition // ""' <<< "$svc")
  public=$(jq -r '.networkConfiguration.awsvpcConfiguration.assignPublicIp // ""' <<< "$svc")

  # taskDefinition can be a family, family:revision or a full ARN depending on
  # the build, so always resolve it to what is really registered.
  taskdef="UNKNOWN"; roles="UNKNOWN"
  if [ -n "$td_ref" ] && td=$(aws ecs describe-task-definition --task-definition "$td_ref" \
                                --query 'taskDefinition' --output json 2>/dev/null); then
    taskdef="$(jq -r '"\(.family):\(.revision)"' <<< "$td")"
    exec_arn=$(jq -r '.executionRoleArn // ""' <<< "$td")
    task_arn=$(jq -r '.taskRoleArn // ""' <<< "$td")
    if [ -z "$exec_arn" ] || [ -z "$task_arn" ]; then roles="UNKNOWN"
    elif [ "$exec_arn" = "$task_arn" ]; then roles="SAME"
    else roles="SEPARATE"; fi
  fi

  case "$public" in
    ENABLED)  publicip="RISK" ;;
    DISABLED) publicip="OK" ;;
    *)        publicip="N/A" ;;
  esac

  printf '%-20s desired=%-2s running=%-2s taskdef=%-18s roles=%-9s publicip=%s\n' \
    "$name" "$desired" "$running" "$taskdef" "$roles" "$publicip"

  records=$(jq --arg n "$name" --arg d "$desired" --arg r "$running" --arg t "$taskdef" \
               --arg ro "$roles" --arg p "$publicip" \
               '. + [{service:$n,desired:$d,running:$r,taskDefinition:$t,roles:$ro,publicIp:$p}]' \
               <<< "$records")
done

jq . <<< "$records" > "$OUT"
