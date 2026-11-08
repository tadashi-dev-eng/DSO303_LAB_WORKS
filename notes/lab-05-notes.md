# Lab 05 notes

**Support path: B (control plane only).** Every ELBv2 object was created and can be read back, but the target group never received a target and the load balancer serves no requests. Floci server 1.7.0, CLI 0.2.0. The ECS service does not retain its `loadBalancers` entry or grace period, which the course's Known Issues page lists for Lab 05 on Floci 2.0.1 and which I saw on this build too.

Run `export AWS_DEFAULT_REGION=us-east-1` first in any new terminal, because the `floci` profile's region is `ap-south-1`.

## Your turn answers

**Step 4 (HTTPS).** The load balancer has no HTTPS listener on 443 and no TLS certificate for it. AWS Certificate Manager issues the certificate for free, but the domain name it is issued for, and the ability to add a DNS record proving control of it, has to come from outside AWS.

**Step 6 (matcher).** (a) An application that redirects `/` to `/login` answers 302, so a strict 200 matcher marks it unhealthy forever. (b) It would be a bug in my work, because the script states the configuration the lab specified, and a verification script exists to report when the system differs from what was agreed.

**Step 11 (self-registration).** Without service-managed registration, I would have to register each new task's address and deregister each stopped one by hand after every scaling event. On this build the target group stayed empty through the change to 3 and back, so I saw the desired count move but not the registration.

## Floci limitations observed, and what real AWS would do

| Observed on Floci | Real AWS |
|---|---|
| `update-service --load-balancers --health-check-grace-period-seconds` accepted, but `loadBalancers` and the grace period read back `null` | Both are stored, and the service registers its tasks |
| Target group stayed empty through a scale to 3 and back | Each task is registered and deregistered by the service |
| `healthStatus` and task IP read back `None` from `describe-tasks` | The health status and the ENI's private address are returned |
| ALB DNS name `*.elb.floci` does not resolve, so `curl` could not connect | The name resolves to the load balancer nodes |
| `revoke-security-group-ingress --security-group-rule-ids` returned `True` and removed nothing | The rule is removed |
| After revoking by `--ip-permissions`, `describe-security-group-rules` still listed the old rule ID, while `describe-security-groups` no longer showed it | The two views agree |
| `--force-new-deployment` left the task IDs unchanged | Every task is replaced in a rolling deployment |
| `events` returned `None` on the service | Events narrate target registration and draining |
| `describe-rules` returned path values under `PathPatternConfig.Values`, with `Values` empty | Both forms are returned |
| `elbv2 describe-listeners --load-balancer-arn probe` returned an empty list | Returns a `ValidationError` for a malformed ARN |
| The `instance.group-id` filter returned instances without the group | Only instances carrying the group are returned |

## Lab typos found while running it

- Step 14 uses `--query 'length(deployments)'` on `describe-services`. The field is under `services[0]`, so the query errors and the loop always runs to its limit. `length(services[0].deployments)` works.
- Step 18 escapes the backticks as `` \` `` inside `$(...)` in a heredoc. The single quotes already protect them there, so the escaped form is a bad JMESPath expression and the listener value came out empty. I looked the value up without the escaping and corrected that one line.
- The comments in `lab-05-cleanup.sh` name `lab-04-cleanup.sh` as both the script to run before and after. The first should be Lab 06's. The script is copied verbatim and was not run.

## Observed versus reasoned about (Section 11, annotated for this build)

| Observed on this build | Reasoned about only |
|---|---|
| ALB, target group, listener and rule all created and read back | A served request through the listener |
| Scheme, type, two AZs, one security group | Real load balancer nodes and public DNS resolution |
| Target group health settings and the deregistration delay stored | Health checks being executed |
| Target group attached to one load balancer (0 to 1) | Targets registered by the service, and initial/healthy/draining states |
| `/alb-health` rule listed ahead of the default action | Rule evaluation, fixed responses, redirect, HTTPS |
| Security group chain changed, including the cutover | Security group enforcement on packets |
| Lab 04's script changing by exactly one check after the cutover | Connection draining during a deployment |
| Configuration surviving a restart | The service's `loadBalancers` entry surviving a restart, because it was never stored |
| `desiredCount` following changes to 3 and back to 2 | Real cost, which Exercise 4 calculates from list prices |

## Verification

`verify-lab-05.sh` reports `PASS=42 FAIL=7`:

| Failing check | Cause |
|---|---|
| service has exactly ONE loadBalancers entry | Floci does not retain it |
| it names usms-enrolment-tg | Same cause |
| containerName is enrolment-api | Same cause |
| containerPort is 80 | Same cause |
| healthCheckGracePeriodSeconds is set | Same cause; listed as benign by the lab |
| configs/lab-05.env has no empty values | `USMS_SVC_LB_CONTAINER`, `USMS_SVC_LB_PORT` and `USMS_SVC_GRACE_PERIOD` are `None` because they are looked up from the same missing fields |
| no secret is tracked by git | False positive on `outputs/.gitkeep`, as in Labs 2 and 4 |

## ECS and load balancer health side by side (Step 11)

| ECS healthStatus | Target health | Diagnosis |
|---|---|---|
| HEALTHY | healthy | Working |
| HEALTHY | unhealthy | The network path is broken: security group, subnet, or the health check path returning the wrong code |
| UNHEALTHY | unhealthy | The application is broken; read the container logs |
| UNKNOWN | healthy | Not a fault: the task definition has no container health check |
| anything | unused | Nothing forwards to this target group |

On this build `healthStatus` was `None` and there were no targets, so I could not fill the table from live output.

## Review questions

**1. Group references and load balancers.** Both give a stable thing to point at when the real addresses keep changing. A security group reference lets a rule name a role instead of addresses, and a load balancer lets clients name one endpoint instead of task addresses. The general problem is indirection: separating the identity of a service from its current location. DNS is a third solution, since a name stays constant while the address behind it changes.

**2. "The health check says unhealthy, so the application is broken."** That is unsound because the check is run by the load balancer over the network, so it fails just as easily when the network is the problem. It cannot distinguish a broken application from a working application it cannot reach. ECS's `healthStatus`, from the container health check run inside the task, does separate them, and `TargetHealth.Reason` tells a timeout from a failed response. I would compare `healthStatus` with target health, read the reason, then check the security group, health check path, matcher and port in that order.

**3. No update-target-group-target-type.** It shows that some fields define what a thing is, and others only how it behaves. Target type is identity, like a task definition revision, which you replace and never edit. The load balancer's scheme and the target group's VPC behave the same way. The health check matcher looks as if it should be fixed, but `modify-target-group` changes it immediately, as Step 6 showed.

**4. A request as ECS stops its task.** The timers are `deregistration_delay.timeout_seconds` on the target group (30 seconds) and `stopTimeout` in the task definition, with `minimumHealthyPercent` on the service governing capacity. If the task is already `draining`, the load balancer sends the new request to another target and it succeeds. If it was forwarded just before draining, it is in flight and has up to 30 seconds to finish before SIGTERM. At 300 seconds it would still succeed, but every task replaced in a deployment could hold up the rollout for five minutes. I reasoned this through; draining could not be observed on this build.

**5. Updating Lab 04's script, or leaving it.** Update it now: it describes a system that no longer exists, and a permanently red check teaches people to ignore red. Leave it: it records what Lab 04 built, and a failure with a written explanation is honest history. With four other engineers I would update it in the same commit as the change, because they would otherwise lose time on a failure they did not cause. Working alone I might leave it for a while, since I am the only person who has to remember why it is red.

**6. Internet-facing with private tasks.** The load balancer's nodes sit in `usms-public-subnet-a` and `-b`, whose `usms-public-rt` routes to `usms-igw`, so they have public addresses. The tasks sit in `usms-private-subnet-a` and `-b`, whose `usms-private-rt` has only `usms-nat` and `usms-s3-endpoint`, inside `usms-vpc`, so there is no inbound route to them. Both are true because the load balancer terminates the connection and opens a new one to the tasks, which `usms-enrolment-sg` permits only from `usms-alb-sg`. An attacker who controlled its configuration could send traffic to any address the load balancer can reach through a target group, but only over paths its security group allows. With public task addresses, an attacker would not need the load balancer at all, and one wrong security group rule would expose every task.

**7. Requests per target versus CPU.** Requests per target measures the demand itself, and it rises before CPU saturates, so scaling starts sooner. CPU is better where the work is not driven by requests, such as a background worker reading a queue. `ALBRequestCountPerTarget` would scale the enrolment application badly if its requests varied greatly in cost, or if the real bottleneck was the database, because more tasks would only put more load on it.
