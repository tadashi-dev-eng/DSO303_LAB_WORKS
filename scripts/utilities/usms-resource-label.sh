#!/usr/bin/env bash
# Lab 05 Exercise 5 - derive Lab 06's ALBRequestCountPerTarget ResourceLabel from the API.
# usage: usms-resource-label.sh [load-balancer-name] [target-group-name]
# Prints app/<lb>/<lb-id>/targetgroup/<tg>/<tg-id>. Read-only; runs from any directory.
# Reads no configs/lab-05.env value, and contains or reads no access key.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env"
export AWS_DEFAULT_REGION="$AWS_REGION_COURSE"

LB_NAME="${1:-usms-enrolment-alb}"
TG_NAME="${2:-usms-enrolment-tg}"

lb_arn=$(aws elbv2 describe-load-balancers --names "$LB_NAME" \
           --query 'LoadBalancers[0].LoadBalancerArn' --output text) \
  || { echo "cannot read load balancer $LB_NAME" >&2; exit 1; }
tg_arn=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
           --query 'TargetGroups[0].TargetGroupArn' --output text) \
  || { echo "cannot read target group $TG_NAME" >&2; exit 1; }

# The two suffixes need different treatment. The label keeps the word "targetgroup"
# but drops the word "loadbalancer", so the load balancer needs that prefix removed,
# while the target group's last colon-separated ARN field is already the right text.
lb_suffix="${lb_arn#*:loadbalancer/}"
tg_suffix="${tg_arn##*:}"
label="$lb_suffix/$tg_suffix"

# Refuse to print anything that could not be a real ResourceLabel.
IFS=/ read -r -a segments <<< "$label"
if [ "${#segments[@]}" -ne 6 ] || [ "${segments[0]}" != app ] \
   || [ "${segments[1]}" != "$LB_NAME" ] || [ "${segments[3]}" != targetgroup ] \
   || [ "${segments[4]}" != "$TG_NAME" ]; then
  echo "implausible ResourceLabel: $label" >&2
  exit 1
fi

echo "$label"
