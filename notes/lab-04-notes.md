# Lab 04 notes

**Support path: A (full), with caveats.** ECS and the Application Auto Scaling targets and policies answered. `describe-scheduled-actions` did not answer, which the course's Known Issues page lists for Lab 06. The probe printed "not available" for `ecs describe-services`, but only because the probe treats the expected `ClusterNotFoundException` as a failure: the real call works, as Steps 10 and 11 show.

## Environment finding

The `floci` profile in `~/.aws/config` has `region = ap-south-1`, while all course resources are in `us-east-1`. With the profile's region, `verify-lab-02.sh` gave `PASS=18 FAIL=15` and `verify-lab-03.sh` gave `PASS=17 FAIL=19`. Running `export AWS_DEFAULT_REGION=us-east-1` in the session fixed both without changing the profile. Any new terminal needs that export again.

## Floci limitations observed, and what real AWS would do

| Observed on Floci | Real AWS |
|---|---|
| `describe-clusters --include SETTINGS` returned `Settings: null` | Returns `containerInsights = enabled` and publishes per-service metrics to CloudWatch |
| `logConfiguration` is accepted at registration and dropped on `describe-task-definition` | The awslogs configuration is stored and returned |
| `assume-role` returned the session name `floci-session`, not `lab04-ecs-build` | The ARN carries the requested session name |
| Service `taskDefinition` read back as the family name `usms-enrolment` | A full task definition ARN including the revision |
| `events` on the service returned `None` | The service's events list narrates placement and scaling |
| `list-tasks` included a STOPPED task | `list-tasks` returns RUNNING tasks unless `--desired-status STOPPED` is passed |
| `update-service` to revision 2, even with `--force-new-deployment`, did not replace running tasks | A rolling deployment replaces them |
| `instance.group-id` filter returned instances that do not carry the group | Only instances carrying the group are returned |

Task credentials through `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`, security group enforcement on task traffic, Fargate start latency and cost were not observed and are reasoned about only.

## Verification

`verify-lab-04.sh` reports `PASS=37 FAIL=1`. The single failure, `no secret is tracked by git`, is a false positive: the check fails on any tracked path under `outputs/`, and the only one is `outputs/.gitkeep`, which Step 13 of the lab expects to be tracked. `git ls-files` shows no key, credential or `.env` file. The same check fails in `verify-lab-02.sh` for the same reason.

## Two delivery mechanisms, one policy

Lab 03: `usms-web-01` -> instance profile -> `usms-ec2-app-role` -> `USMSStudentDataReadWrite`.
Lab 04: task -> `taskRoleArn` -> `usms-ecs-task-role` -> `USMSStudentDataReadWrite`.

Neither has a key on disk, and both start working the moment Lab 10 creates the bucket.

## Review questions

**1. "I put auto scaling on the task definition."**
Almost every part of that is wrong. A task definition is an immutable blueprint, so it has nothing that could scale. Lab 06 registers the ECS *service* as a scalable target with Application Auto Scaling, identified as `service/<cluster>/<service>`. The policy only ever modifies the service's `desiredCount`, and the ECS service controller is the object that makes reality match, by starting or stopping tasks. Because ECS knows nothing about the scalable target, a person can run `update-service --desired-count` and ECS will accept it without any warning, and `describe-services` will not mention scaling at all. You have to ask Application Auto Scaling separately to find out that a policy exists.

**2. One policy, two delivery mechanisms.**
On EC2, the instance profile attaches `usms-ec2-app-role` to the instance, and the code fetches temporary credentials from the instance metadata service. On Fargate, `taskRoleArn` tells ECS which role the task uses, and the SDK inside the container fetches temporary credentials from the endpoint named by `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`. In both cases the credentials are temporary, rotated by AWS and fetched at runtime by the SDK, so no access key is written to disk or baked into an image. Today the policy names a bucket that does not exist, so the permissions have nothing to act on. The moment Lab 10 creates `usms-student-data`, both the instance and the task can read and write objects, with no change to either role, and `DeleteBucket` stays denied for both.

**3. Telling the two roles apart.**
If the execution role is wrong, the task never starts and `stoppedReason` mentions the image pull or logs; if the task role is wrong, the task starts and the application then gets `AccessDenied`. They share an identical trust policy because trust only answers who may assume the role, and in both cases that is `ecs-tasks.amazonaws.com`. What separates them is the permissions attached and which part of the system uses them.

**4. A group reference instead of a CIDR.**
Even if the task count never changed, `10.0.1.0/24` would admit anything in that subnet, while the real requirement is "the web tier", and the group says exactly that. Any instance later given `usms-app-sg` is allowed automatically and anything without it is refused, whichever address it has. Once Lab 06 lets the count change, tasks and web instances come and go with addresses nobody can know in advance, so a list of addresses could not be kept correct, and a group reference never needs updating.

**5. What Fargate removes, and what it does not.**
Fargate removes the instances: no AMI, no patching, no SSH, no key pair, no capacity to manage, and no choice of instance type. It does not remove the network. An awsvpc task still gets its own interface in my subnet, its own security group, and follows Lab 2's route tables, so in a private subnet it still depends on `usms-nat` to reach the registry. It also does not remove IAM or my responsibility for what runs in the container.

**6. Memory versus hybrid mode.**
`aws ecs register-task-definition --generate-cli-skeleton` looks identical in both, because the CLI generates it locally and never contacts Floci. After a restart, `aws ecs describe-clusters --clusters usms-ecs-cluster` would not look identical: in hybrid mode the state is on disk at `~/floci-data` and it returns ACTIVE, while in memory mode the state is gone and the cluster comes back missing. That is the same lesson as Lab 1 Step 14: an answer that does not depend on stored state proves nothing about persistence. I reasoned this out; I did not restart Floci during this lab.
