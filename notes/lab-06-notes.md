# Lab 06 notes

**Support path: B (control plane only).** Floci server 1.7.0 (`floci/floci:latest`, image `fbd0441e3512`), AWS CLI 2.31.24. The scalable target, all three scaling policies, the four managed alarms, the custom metric and its alarm are created, read back and survive a restart. Alarms never evaluate on their own, `set-alarm-state` changes the state but does not invoke the policy, and `desiredCount` never moves unless I set it. `PutScheduledAction`, `DescribeScheduledActions`, `DeleteScheduledAction` and `DescribeScalingActivities` all return `UnsupportedOperation`. The course's Known Issues page lists the same gaps for Lab 06 on Floci 2.0.1.

Run `export AWS_DEFAULT_REGION=us-east-1` first in any new terminal, because the `floci` profile's region is `ap-south-1`.

## Your turn answers

**Step 6 (MinCapacity 5).** Prediction: `desiredCount` moves from 2 to 5 within seconds, with no policy and no alarm involved. Observed on this build: Floci stored `MinCapacity 5` but `desiredCount` stayed at 2 for three polls, and `describe-scaling-activities` is unsupported, so the change was not recorded either. I put the floor back to 2.
(a) The scalable target made the change. A registration enforces its own bounds, and ECS only applies the number it is given.
(b) Three extra Fargate tasks run all night (about 3 x $0.0123 = $0.037 an hour at the task size in `configs/lab-04.env`), and every scale-in below 5 is silently blocked. `aws application-autoscaling describe-scalable-targets --query 'ScalableTargets[0].MinCapacity'`, compared with `USMS_ECS_DESIRED_BASELINE`, would have shown it.

**Step 8 (time to a third serving task at 100 per cent CPU).**
1. The high alarm's `Period x EvaluationPeriods` = 60 s x 3 = **180 s**.
2. Policy invocation, about **0 s**.
3. Task start-up, **30 s**. Not measured here (Floci never started a task from a scaling decision). AWS documents about 30 s to provision Fargate capacity.
4. Lab 05's health-check grace period, **60 s**.

Total about **270 s**, or four and a half minutes, served by two tasks. Only the grace period is in this lab's own configuration; the alarm shape is AWS's and the start-up time is the image's. The term I would change first is the grace period: it is mine to set and it is the largest term I control. The cost is that a task that genuinely takes longer to become healthy would be killed and replaced in a loop.

**Step 11 (`at()` action).** `put-scheduled-action` returned `UnsupportedOperation`, so nothing was created and the mechanism was not observable. On real AWS, an `at()` action stays after it fires: the record is left behind, and so is the raised floor of 6. Six months later the leftover action confuses anyone reading the scaling configuration, and the CloudFormation lab would template it. The runbook page that creates it should also hold `delete-scheduled-action --scheduled-action-name usms-enrolment-results-night`, followed by `register-scalable-target --min-capacity 2`, because deleting the action does not undo the floor.

## Step 15: the nine-line chain

1. A student clicks Register; requests per target rise past 1000, or the work queue passes 100. (block 1, **this lab**)
2. An alarm fires and invokes a policy. (blocks 1-2, **this lab**)
3. The policy writes `desiredCount`, clamped to 2..10. (block 3, **this lab**)
4. ECS starts a task from `usms-enrolment:2`. (block 4, Lab 04)
5. The task gets an ENI in `usms-private-subnet-a` or `-b`, with no public address. (block 5, Lab 02/04)
6. `usms-enrolment-sg` admits tcp/80 from `usms-alb-sg` only. (Lab 05)
7. The service registers the task's address in `usms-enrolment-tg`. (block 6, Lab 05)
8. The load balancer health-checks it, and after 60 s of grace it takes traffic. (blocks 4 and 6, Lab 05)
9. Nothing about the blueprint, the service or the load balancer changed. (block 7)

This lab owns lines 1 to 3. On this build, block 6 is empty and the grace period reads `None`, because Floci did not keep Lab 05's service attachment; that is a Lab 05 limitation, not something this lab changed.

## Floci limitations observed, and what real AWS would do

| Observed on Floci 1.7.0 | Real AWS |
|---|---|
| `create-service-linked-role` created `AWSServiceRoleForEcsApplicationAutoscaling`, not `AWSServiceRoleForApplicationAutoScaling_ECSService`, with no attached policy. The scalable target's `RoleARN` names the AWS name, a role that does not exist here | The role has the documented name and `AWSApplicationAutoscalingECSServicePolicy`, and it is genuinely assumed |
| `register-scalable-target --min-capacity 5` stored the bound but `desiredCount` stayed 2 | Registration raises `desiredCount` to the floor immediately |
| Managed alarms use metric name `ECSServiceAverageCPUUtilization` (and `ALBRequestCountPerTarget` under `AWS/ECS`), with high and low both at threshold 50 | `AWS/ECS CPUUtilization` and `AWS/ApplicationELB RequestCountPerTarget`, with a lower scale-in threshold (dead band) |
| The step policy's `Alarms` list is empty although `usms-enrolment-queue-high` names it | `describe-scaling-policies` lists the alarm that invokes the policy |
| Alarm stayed `INSUFFICIENT_DATA` / `Unchecked` after datapoints of 260 | Evaluated every period; goes to `ALARM` within a minute |
| `set-alarm-state ALARM` changed the state; `desiredCount` stayed 2 | The alarm action invokes the step policy; 2 -> 5 with an activity naming the alarm and policy |
| `PutScheduledAction`, `DescribeScheduledActions`, `DeleteScheduledAction`, `DescribeScalingActivities`: `UnsupportedOperation` | All implemented |
| `DisableScaleIn: true` policy still got an `AlarmLow` (six managed alarms instead of five) | No low alarm is created for a scale-out-only policy |
| Suspension switches are stored but have nothing to suspend | Suspension blocks the corresponding scaling actions |
| After `floci-down.sh`/`floci-up.sh` the container exited during start-up while `docker ps` still showed it as running; `floci-up.sh` timed out | Not applicable; a second stop/start brought it back with all state intact |

## Lab typos found while running it

- **Step 16** writes `awk -F: '{print \$NF}'` inside `$(...)` in an unquoted heredoc. The single quotes already protect `$NF` there, so awk receives `\$NF`, prints `awk: unexpected character '\'`, and `USMS_SCALABLE_RESOURCE_ID` is written empty. I filled the value in from the API and recorded the fix; `'{print $NF}'` without the backslash works.
- **Step 17 part 1** replaces every `lab-04-cleanup.sh` in `lab-05-cleanup.sh`. In this repository's copy, two of those five occurrences are correct (`Run BEFORE lab-04-cleanup.sh` and `lab-04-cleanup.sh may now run`), so I replaced only the three that name the script to run first. `lab-04-cleanup.sh` contained no occurrence.
- **Steps 2 and 15** use `length(loadBalancers)`. On this build the field is `null`, so the whole query fails; `length(loadBalancers || \`[]\`)` works.
- `verify-lab-04.sh`'s `no secret is tracked by git` check is flaky: `git ls-files | grep -q` under `set -o pipefail` sometimes fails with SIGPIPE, so the same tree reports `PASS=38 FAIL=1` or `PASS=39 FAIL=0`.

## Observed versus reasoned about (Section 11, annotated for this build)

| Observed on this build | Reasoned about only |
|---|---|
| Service-linked role (under Floci's name) | The role being assumed, and CloudTrail naming it |
| Scalable target, bounds, re-registration change model | Registration enforcing the floor |
| Three policies, four managed alarms, ResourceLabel | The target tracking capacity calculation, cooldowns |
| Custom metric and `get-metric-statistics` | Alarm evaluation each period |
| Custom alarm wired to the step policy (six-block chain) | A scaling activity with its Cause string |
| Step selection (breach 160 -> +3), computed from the template | `desiredCount` 2 -> 5 by a policy |
| Suspension switches stored and cleared | Suspension stopping a scaling action |
| Restart persistence of every object | Scheduled actions (unsupported) |
| Manual scale to 5 and back (Known Issues alternative 2) | Fargate start latency and the grace period |

## Review questions

**1. What does auto scaling change about my application?** The nine lines are listed above. This lab owns the first three: the metric crossing a threshold, the alarm invoking a policy, and the policy writing `desiredCount` within 2..10. The other six needed no change because ECS already turns a desired count into tasks, Lab 02 already gave those tasks two private subnets, Lab 05's security group already admits any task in the group, the service already registers whatever tasks it runs, and the load balancer already health-checks whatever is registered. Auto scaling changes one integer about my application, and who is allowed to write it.

**2. The resource ID.** The resource ID is a constructed string naming the resource inside its namespace, not an ARN: for ECS it is `service/<cluster>/<service>`, the part of the service ARN after the last colon. Application Auto Scaling uses one addressing scheme (namespace, resource ID, dimension) for nine very different services, and an ARN format differs per service, so the scaler takes a short, uniform path. For DynamoDB it is `table/<table>` (or `table/<table>/index/<index>`) with dimensions such as `dynamodb:table:ReadCapacityUnits`; for Lambda it is `function:<name>:<alias>` with `lambda:function:ProvisionedConcurrency`. The other constructed identifier in this architecture is the `ResourceLabel`, `app/<alb>/<id>/targetgroup/<tg>/<id>`, built from the load balancer ARN after `:loadbalancer/` and the target group ARN after its last colon. The policy ARN in turn embeds the resource ID.

**3. Registration raising the count.** The scalable target makes that change: registering with a minimum of 2 is a statement that the service may not be below 2, and Application Auto Scaling enforces it at once. A policy makes a change in response to a metric, through an alarm, and leaves an activity naming that alarm. A bound change has no alarm behind it. At 3 a.m. an on-call engineer under a traffic incident raises `MinCapacity` to 6 so that no policy can shrink the service while they investigate. The person who takes over at 8 has `describe-scalable-targets` showing `MinCapacity 6` against a baseline of 2, an activity on real AWS describing a desired count set to 6 with no alarm in its cause, and CloudTrail recording the `RegisterScalableTarget` call and who made it. Unless the engineer wrote it down, that is all they have.

**4. Managed alarms versus my alarm.** The two `TargetTracking-...` alarms belong to the target tracking policy: Application Auto Scaling creates them, overwrites them whenever the policy changes, and deletes them with it. If one is deleted, the policy keeps listing it but no longer scales in that direction. `usms-enrolment-queue-high` is mine: nothing changes or deletes it but me, and it can do what a managed alarm cannot, for example notify an SNS topic as well as invoking the policy, or use any statistic, period and missing-data treatment I choose. The argument for `breaching` is that the queue depth is published by the application, so silence most likely means the publisher is broken during load, and the safe reaction is to add capacity. If I were right and set it, any publisher outage (a deploy, a crashed sidecar) would scale the service out by three tasks every minute until the ceiling, and would cost money on a quiet night for a problem that capacity cannot fix.

**5. Why reactive scaling is late.** From Step 8: 180 s for the high alarm (the 60 s period and 3 evaluations, set by AWS for target tracking), about 0 s to invoke the policy, about 30 s for Fargate to start a task (image size and AWS), and 60 s of health-check grace (`healthCheckGracePeriodSeconds`, Lab 05). That is about 270 s during which two tasks carry the spike. The three consequences: the minimum capacity is a latency decision, which justifies a floor of 2, one per AZ, instead of 1; scale out eagerly and scale in reluctantly, which justifies `ScaleOutCooldown 60` against `ScaleInCooldown 300`; and a known spike must be scheduled, which justifies the 07:45 morning action raising the floor to 4 before enrolment traffic starts.

**6. Two policies disagreeing.** On scale-out, the largest capacity any policy asks for wins, so the CPU policy can add tasks while the request policy is content, and the reverse. On scale-in, the service shrinks only when every policy with scale-in enabled agrees. The rule is asymmetric because the costs are: too many tasks for a few minutes costs a little money, while too few drops requests. Two target tracking policies on the same metric with different targets fight, because each one's correction moves the metric past the other's target, and the service oscillates. A step policy and a target tracking policy on one metric are the same mistake, because the step policy adds fixed tasks at its threshold, which pushes the metric below the target tracking policy's low threshold, so it scales back in.

**7. ALBRequestCountPerTarget versus CPU.** It measures the cause (requests) rather than a symptom (CPU); it does not depend on the 256-unit CPU reservation, so it stays correct if the task size changes; and it moves as soon as load arrives, without waiting for work to queue up in the process. CPU is better for CPU-bound work whose cost per request varies widely, such as report generation or PDF rendering, where 100 cheap requests and 100 expensive ones are not the same load. Request count would scale this service badly if the bottleneck were downstream, for example the database: more tasks would push more queries into a saturated database while each task's request count looked healthy. `TargetResponseTime` (or the database's own CPU and connection count) rising while requests per target stays flat would have warned me.
