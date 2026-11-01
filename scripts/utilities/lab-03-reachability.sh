#!/usr/bin/env bash
# Reachability report: one line per running instance tagged Project=USMS.
# The verdict is computed only from route tables, public addresses and
# security groups -- never from names or tags. Read-only; safe to run anytime.
#
# No 'set -e': a missing field, an empty query result or a non-matching jq
# filter is a normal state here (e.g. a private instance has no public IP),
# not an error. The AWS calls that really matter are checked explicitly below,
# so a genuine failure still stops the script with a clear message.
set -uo pipefail

# Resolve the repo from the script's own location, so the output is the same
# whatever directory it is run from. We never cd and never use relative paths.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

fetch() {  # fetch <label> <aws args...> : prints JSON or aborts
  local out
  if ! out=$(aws "${@:2}" --output json 2>&1); then
    echo "failed to read $1: $out" >&2; exit 1
  fi
  printf '%s' "$out"
}

INSTANCES=$(fetch instances ec2 describe-instances \
  --filters "Name=tag:Project,Values=USMS" "Name=instance-state-name,Values=running")
ROUTES=$(fetch "route tables" ec2 describe-route-tables)
SGS=$(fetch "security groups" ec2 describe-security-groups)
EIPS=$(fetch "elastic IPs" ec2 describe-addresses)

jq -r -n \
  --argjson inst "$INSTANCES" --argjson rt "$ROUTES" \
  --argjson sg "$SGS" --argjson eip "$EIPS" '
  # Route table for a subnet: its explicit association, else the VPC main table.
  def table($subnet; $vpc):
    ([$rt.RouteTables[]? | select(any(.Associations[]?; .SubnetId == $subnet))][0])
    // ([$rt.RouteTables[]? | select(.VpcId == $vpc and any(.Associations[]?; .Main == true))][0]);

  def igw_default_route($t):
    any($t.Routes[]?; (.DestinationCidrBlock // "") == "0.0.0.0/0"
                      and ((.GatewayId // "") | startswith("igw-")));

  # Does any attached SG allow 80/tcp from 0.0.0.0/0 ("-1" = all traffic)?
  def sg_allows_80($ids):
    any($sg.SecurityGroups[]? | select(.GroupId as $g | $ids | index($g)) | .IpPermissions[]?;
        (.IpProtocol == "-1"
         or (.IpProtocol == "tcp" and (.FromPort // 65536) <= 80 and (.ToPort // -1) >= 80))
        and any(.IpRanges[]?; .CidrIp == "0.0.0.0/0"));

  [$inst.Reservations[]?.Instances[]?]
  | sort_by((.Tags // [] | map(select(.Key == "Name"))[0].Value // ""), .InstanceId)
  | .[]
  | . as $i
  | ($i.Tags // [] | map(select(.Key == "Name"))[0].Value // $i.InstanceId) as $name
  | ([$eip.Addresses[]? | select(.InstanceId == $i.InstanceId) | .PublicIp][0]
     // $i.PublicIpAddress // "-") as $pub
  | table($i.SubnetId // ""; $i.VpcId // "") as $t
  | [($i.SecurityGroups // [])[] | .GroupId] as $sgids
  | (if ($t == null or (igw_default_route($t) | not)) then
       ["UNREACHABLE", "no igw route on subnet"]
     elif $pub == "-" then
       ["NO-ADDRESS", "igw route present but no public address"]
     elif (sg_allows_80($sgids) | not) then
       ["BLOCKED", "igw route + public address but no sg rule allows 80/tcp from 0.0.0.0/0"]
     else
       ["REACHABLE", "igw route + sg allows 80/tcp from 0.0.0.0/0"]
     end) as $v
  | [$name, ($i.PrivateIpAddress // "-"), $pub, $v[0], $v[1]] | @tsv' |
while IFS=$'\t' read -r name priv pub verdict reason; do
  printf "%-20s %-15s %-15s %-13s %s\n" "$name" "$priv" "$pub" "$verdict" "$reason"
done
