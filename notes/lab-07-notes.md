## Lab 07 support path
Probed on 2026-11-10T17:57:08Z
PATH A  - use aws eks throughout

Floci server 1.7.0, AWS CLI 2.31.24, kubectl 1.36.3, Docker Desktop (VM with 3.5 GiB). `aws eks create-cluster` starts a real k3s container (`floci-floci-course-eks-usms-eks-cluster`, `rancher/k3s:latest`) and publishes its API server on `https://localhost:6501`. The Kubernetes half of this lab is real; the node group, its instance type and the IAM policies are records.

Run `export AWS_DEFAULT_REGION=us-east-1` first in any new terminal, because the `floci` profile's region is `ap-south-1`.

**Resource note.** The Docker Desktop VM has 3.5 GiB. With the separate `dso202` kind cluster (three nodes, about 3 GB) running, the k3s API server timed out on TLS handshakes and a `kubectl apply` was lost. I stopped the three `dso202` containers (`docker stop`, not removed) for the lab. After that the API answered in about one second.

## Step 3 - "EKS is just ECS with different names"

**False because:** EKS has a data plane I run. The nodes are EC2 instances in my account with a kubelet I patch, and they need their own node role that trusts `ec2.amazonaws.com`, separate from the cluster role that trusts `eks.amazonaws.com`. On ECS with Fargate that whole right-hand column is AWS's job.

**Nearly true because:** the objects line up one-to-one in purpose: a task definition is a pod template, a service keeping N tasks alive is a Deployment and its ReplicaSet, and a rolling deployment is a rolling update. Both run containers from an image with a desired count and replace failed ones.

## Your turn answers

**Step 9 (version and OIDC issuer).** `1.30  https://oidc.eks.us-east-1.amazonaws.com/id/0F140EA1B0FA48ABB37440AF1B1D83AD`. The issuer is the URL where the cluster publishes the public keys that sign its ServiceAccount tokens. IAM trusts it as an identity provider, so STS can verify a pod's token and exchange it for role credentials (IRSA). This build advertises an issuer, but the k3s API server's own issuer is `https://kubernetes.default.svc.cluster.local` (Step 21).

**Step 16 (replacement pod).** After deleting `usms-enrolment-6965b8dbbb-84wx5`, the **ReplicaSet** `usms-enrolment-6965b8dbbb` created `usms-enrolment-6965b8dbbb-lckg9` (event `SuccessfulCreate` from `replicaset/usms-enrolment-6965b8dbbb`). Twelve requests through the gateway afterwards all succeeded, split 2/10 between the survivor and the new pod. The Deployment only manages ReplicaSets; the ReplicaSet keeps the pod count.

**Step 18 (rolling `usms-results` by image).** `nginx:1.27-alpine` -> `nginx:1.27` -> undo. `kubectl rollout history` lists **two** revisions afterwards (4 and 5): undo re-uses the old template as a new revision number and drops the duplicate. The peak was **3 pods**, the same shape as `usms-enrolment`. With two replicas, the default 25% surge rounds up to 1 and 25% unavailable rounds down to 0, so the default behaves exactly like `maxUnavailable: 0, maxSurge: 1` at this size; it would differ from four replicas upward.

## Step 20 - ECS and Kubernetes, compared with both running

| Question | ECS answer | Kubernetes answer |
| --- | --- | --- |
| What holds the container spec? | Task definition `usms-enrolment:2` (registered, versioned) | Pod template inside the Deployment `usms-enrolment` |
| What keeps N copies alive? | The ECS service (`desiredCount 2`) | The ReplicaSet the Deployment owns (`replicas: 2`) |
| What gives it a stable name? | A load balancer target group (Lab 05) or Cloud Map | A ClusterIP Service `usms-enrolment` (10.43.234.26) |
| How does another service find it? | Load balancer DNS name, or Service Connect / Cloud Map | Cluster DNS: `usms-enrolment.usms.svc.cluster.local` via CoreDNS |
| What does a rolling update create? | A new deployment of a new task definition revision | A new ReplicaSet with a new pod-template hash |
| Where does rollback state live? | Old task definition revisions, kept forever | Old ReplicaSets scaled to 0, up to `revisionHistoryLimit` (5) |
| Which IAM role does the app code use? | The task role (`usms-ecs-task-role`) | The node role here (`usms-eks-node-role`), or an IRSA role per ServiceAccount on real EKS |
| What would I have to change to move to another cloud? | Everything: task definitions, services and roles are AWS-only | The manifests move unchanged; IAM roles, the VPC, the node group and load-balancer annotations do not |

For USMS I would choose ECS on Fargate. The team is small and the load is seasonal: Fargate removes the node fleet, its patching and the second IAM role, and Application Auto Scaling (Lab 06) already covers the busy months. Kubernetes' portability and richer deployment controls do not pay for the operational work at this size.

## Step 21 - IRSA, step by step on this build

| IRSA step | Outcome here |
|---|---|
| 1. Cluster publishes an OIDC issuer | `describe-cluster` returns `https://oidc.eks.us-east-1.amazonaws.com/id/0F14...`, a record only. The k3s API server's real issuer is `https://kubernetes.default.svc.cluster.local` |
| 2. Register it in IAM | `create-open-id-connect-provider` succeeded: `arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/0F14...` |
| 3. Role with a web-identity trust policy | Not created; nothing could ever assume it here |
| 4. Annotated ServiceAccount | `usms-enrolment-sa` created (`manifests/lab-07/60-serviceaccount.yaml`), not annotated |
| 5. Webhook injects token and env vars | No mutating webhook exists (`kubectl get mutatingwebhookconfigurations`: none) |
| 6. SDK calls `AssumeRoleWithWebIdentity` | Not possible: tokens are signed by an issuer IAM does not know |

So I wrote the ServiceAccount, registered the advertised provider, traced the trust chain, and recorded that steps 3 to 6 cannot complete on this build. IRSA was not configured.

## Floci limitations observed, and what real AWS would do

| Observed on Floci 1.7.0 | Real AWS |
|---|---|
| `create-cluster` took longer than the CLI's read timeout; its retries reported `ResourceInUseException: Cluster already exists`, although the first attempt had created it | Returns at once with status `CREATING` |
| The cluster reports version `1.30`; k3s actually runs `v1.34.1+k3s1` | The control plane runs the requested version |
| One node (the k3s server, role control-plane, no taint) instead of two `t3.small` workers in the private subnets; the node group reports `ACTIVE` immediately | Two EC2 instances join in about five minutes |
| Node group labels `workload=usms`, `tier=app` are not on the node | They are applied to every node in the group |
| Pod IPs are `10.42.0.x` on the k3s network | VPC CNI gives pods addresses from `10.0.3.0/24` and `10.0.4.0/24` |
| IAM policies stored, never evaluated | A missing permission fails cluster creation or node registration |
| Stopping Floci leaves the k3s container running ("Up 22 minutes") | Not applicable |
| `kubectl describe pod` on kubectl 1.36 did not show Events for the broken pods; `kubectl get events` did | Same tools, same behaviour |

## Lab command notes

- `kubectl run ... --rm -it` was run as `--rm -i`, because the commands ran in a non-interactive shell with no TTY. When a `kubectl run -i` with piped output came after another command in the same session, its output was sometimes lost (the pod finished before kubectl attached); running it first fixed this. Screenshot 26's empty tally is that case, and screenshot 27 is the re-run.
- Steps 2 and 20 use `length(loadBalancers)`, which fails because the field is `null` on this build; `length(loadBalancers || \`[]\`)` works.
- `kubectl set env --from=secret/...` on kubectl 1.36 adds two `secretKeyRef` variables, not an `envFrom.secretRef`, so the Step 17 `envFrom` print shows only the ConfigMap. Both keys are in the container.
- Step 18's annotate did not roll (as the lab warns); `rollout restart` did.
- Step 19's `describe pod -l app=usms-results | tail -15` describes all three pods and the tail landed on a healthy one; I described the failing pod by name instead.
- Step 22's two blocks record different fields (before: node group status and Service IPs; after: namespace and ConfigMaps), so the lab's diff always reports differences. A like-for-like comparison was identical.

## Exercise 5 part 3 - what Lab 08 needs from configs/lab-07.env

- `USMS_EKS_CLUSTER` - every `aws eks` call and `update-kubeconfig` names it.
- `USMS_EKS_NODEGROUP` - Lab 08 changes its scaling config from the AWS side.
- `USMS_EKS_NAMESPACE` - Lab 08 works entirely in `usms`.
- `USMS_EKS_CLUSTER_STATUS` - a quick check that the cluster survived before starting.
- `USMS_EKS_ENDPOINT` - shows the API port (6501 here, not 6443) if kubectl loses its context.
- `USMS_EKS_LB_PORTS` - the host ports (8081, 8082) a LoadBalancer Service or Ingress will be published on.
- `USMS_K8S_DEPLOY_ENROLMENT` - the HorizontalPodAutoscaler target.
- `USMS_K8S_CPU_REQUEST` - 50m, the denominator of every HPA utilisation figure.
- `USMS_K8S_SVC_GATEWAY` and `USMS_K8S_DEPLOY_GATEWAY` - the Service Lab 08 turns into a LoadBalancer and puts behind an Ingress.
- `USMS_K8S_MANIFEST_DIR` - where Lab 08's new manifests sit beside these.
- `USMS_EKS_NODE_ROLE_ARN` - the identity any node Lab 08 adds will carry.

Not needed by Lab 08: the cluster ARN, version, cluster role and policy ARNs, the security group, and the results Service and Deployment names. They are kept for the CloudFormation lab and the cleanup script.

## Review questions

**1. ACTIVE but every pod Pending.** `ACTIVE` describes the control plane only: the API server, etcd and the scheduler that AWS runs. Pods need the data plane: nodes that have joined and can take them. The cluster can be healthy while no node can run anything. Two configurations that produce this: a cluster with no node group at all (or one whose instances never join, for example because the node role lacks `eks:DescribeCluster` or trusts the wrong principal), and nodes that exist but cannot fit or tolerate the pods, such as requests larger than any node (Step 19's `usms-toobig`), an unmatched `nodeSelector`, or only control-plane nodes with their `NoSchedule` taint.

**2. Swapping the trust policies.** The cluster role would trust `ec2.amazonaws.com`, so the EKS control plane could not assume it, and `create-cluster` would fail at Step 8 with an error about the role. Had that been fixed, the node role would trust `eks.amazonaws.com`, so the node group's EC2 instances could not get credentials through their instance profile. `create-nodegroup` would accept the request, and the nodes would never join; the group would end in `CREATE_FAILED`, with nodes missing from `kubectl get nodes` at Step 11. On Floci nothing breaks, because trust policies are not evaluated; only reading them (the Step 6 and 7 verify) catches it.

**3. Readiness versus liveness.** Readiness answers "should this pod receive traffic now?": failing it removes the pod from the Service's endpoints and restarts nothing. Liveness answers "is this container wedged beyond recovery?": failing it kills and restarts the container. If a check that slows down under load, such as a database ping, is wired to liveness, a busy moment makes every pod fail together. Kubernetes restarts them all, capacity drops just when it is needed, and the restarted pods are hit even harder. Exercise 3 showed the readiness side: a probe on a path that returns 404 kept both pods out of the Service, while they ran happily.

**4. Rollback is not quite a rollback.** `rollout undo` restored the previous pod template, but the template refers to `usms-app-config` by name, and that ConfigMap was still at 1.1.0, so the pods read 1.1.0. For the image and the template, Kubernetes rollback is a real rollback, and an instant one because the old ReplicaSet is kept. For everything the template references by name (ConfigMaps, Secrets, volumes), it is not: those are separate objects with no revision history. So "not really a rollback" is fair for a release that changed configuration. The fix is to version configuration with the workload: immutable, versioned ConfigMap names (`usms-app-config-v2`), or a hash of the config in a pod-template annotation, as Helm and Kustomize do, so a config change is a template change and undo brings it back.

**5. `maxUnavailable: 0` against the default.** `usms-enrolment` (`maxUnavailable: 0, maxSurge: 1`) adds a new pod, waits for it to become ready, then removes an old one, so capacity never drops below two. It suits a user-facing service such as enrolment during the registration window. The default (25%/25%) may take capacity down by a quarter to roll faster and with less spare room, which suits a batch or internal service with headroom. With only two replicas the two are identical (Step 18's Your turn peaked at 3 pods for both), because 25% of 2 rounds to 0 unavailable and 1 surge. `maxUnavailable: 0` is closer to Lab 04's ECS `minimumHealthyPercent 100`.

**6. "A Secret is encrypted."** It is not. Step 17 printed the stored value and decoded it with `base64 -d`, with no key and nothing beyond `get secret` permission. A Secret keeps the value out of the image and out of `kubectl describe`, can be restricted with RBAC separately from ConfigMaps, and can be mounted or injected without being written into a manifest by hand. It does not encrypt anything by itself, and a committed manifest puts the value in Git history forever. Inside the container it is plain text (`printenv` showed it). On real EKS I would enable KMS envelope encryption of Secrets when creating the cluster, never commit Secret manifests (generate them into `outputs/` or not at all), keep real secrets in AWS Secrets Manager, and use IRSA or EKS Pod Identity so pods need no stored AWS credentials.

**7. ECS or Kubernetes for USMS.** ECS on Fargate. USMS has a small team, one region, and load that is quiet for eight months and busy for two, which Application Auto Scaling handles without a node fleet. This lab made several things harder than Lab 04: two IAM roles instead of one, a node group to size, patch and upgrade separately from the control plane, a second tool (kubectl) with its own credentials and context, a cluster fee on top of the compute, and IRSA instead of a simple task role for pod permissions. What Kubernetes gave me that ECS could not: cluster DNS names for every service with no load balancer in between, instant rollback to a kept ReplicaSet, and manifests that run unchanged on any conformant cluster, plus PodDisruptionBudgets that let the platform refuse a disruption.
