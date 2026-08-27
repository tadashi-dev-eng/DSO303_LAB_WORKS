## 1. Aim / Objective
The Lab 1: IAM is to build AWS from scratch using the principle of least privilege, role-based access control (RBAC), and policy lifecycle management.

## 2. Introduction
Lab 1 is about Setting up Docker, Docker Compose, Git, and Floci emulator with hybrid persistence, as well as configuring the local AWS CLI profile. Moreover it is about building the IAM foundation for and designing an enterprise identity model, configuring role-based access control (RBAC), writing least privilege customer-managed policies, creating trust relationships for EC2/Lambda execution roles, and handling access keys safely.

## 3. Use Case
The use case are : 

1. Human Identity & Role-Based Access Control (RBAC)
2. Temporary Elevated Access (Developer AssumeRole)
3. Application Identity & EC2 Instance Roles
4. Serverless Execution Security (Lambda)
5. Self-Service Credential Management
6. Compliance Auditing & Read-Only Inspection

## 5. Implementation Procedure

### PART A — Environment Setup
- Step 1 - Step 4: Checked system architecture, Docker environment, and installed Floci CLI. Ran floci doctor to ensure readiness.

- Step 5 - Step 6: Created workspace directories (configs, policies, scripts, outputs) and initialized Git, confirming .gitignore blocks secrets in outputs/.
- 
- Step 7 - Step 9: Configured docker-compose.yml with FLOCI_STORAGE_MODE=hybrid and bind mount to ~/floci-data. Launched using floci-up.sh and verified health.
  
- Step 10 - Step 12: Installed AWS CLI v2 and set up the floci profile targeting http://localhost:4566.
  
- Step 13 - Step 15: Ran whoami commands to verify emulator isolation. Checked that data persists on the host.

### PART B — Building the IAM Foundation
- Step 16 - Step 17: Inspected empty account.

- Step 18 - Step 20: Created groups (usms-admins, usms-developers, usms-auditors) and users (usms-admin-01, usms-dev-01, usms-audit-01), and added users to their respective groups.
  
- Step 21 - Step 23: Created customer managed policies (USMSDeveloperBase, USMSStudentDataReadWrite, USMSAssumeAppRoles) and attached ReadOnlyAccess to the auditor group.
  
- Step 24 - Step 25: Used skeletal templates to create inline self-service policies.
  
- Step 26 - Step 27: Inspected the final setup and verified policy versions.
  
- Step 28 - Step 30: Created usms-ec2-app-role (with EC2 trust policy), usms-lambda-exec-role (with Lambda trust policy), and tested sts assume-role for developers.
  
- Step 31 - Step 33: Safely generated access keys and saved lab state.

## Results and Evidence

Writing a .gitignore and initialise Git

![alt text](../../screenshots/lab-1/gitignore.png)

![alt text](../../screenshots/lab-1/git.png)

Ran the ./scripts/setup/floci-up.sh and the floci image is created and was able to access http://localhost:4566

![alt text](../../screenshots/lab-1/flocish.png)

![alt text](../../screenshots/lab-1/floci-web.png)

Verifying if the floci in three independent ways (docker, floci status and curl) and found the floci is ready.

![alt text](../../screenshots/lab-1/floci-check.png)

Created the floci AWS CLI profile

![alt text](../../screenshots/lab-1/profile.png) 

---
```cmd 
Your turn

Run aws configure list --profile floci. Identify which column tells you where each value came from, and explain why the Type for the access key says shared-credentials-file.
```
![alt text](../../screenshots/lab-1/aws-config.png)

The ``TYPE`` column specifies where the AWS CLI resolved each setting from like we can see manual, shared credentials files and config-file. The type column says shared credentials files because AWS CLI separates non-sensitive settings from credentials. Non-sensitive configurations are saved in ~/.aws/config but sensitive credentials are kept in ~/.aws/credentials.

---

### Part B

Checking IAM service and IAM user in the account. An empty list indicates that the account exists but it has no users yet.

![alt text](../../screenshots/lab-1/iamuser.png)

Checking the IAM user data in three formats

![alt text](../../screenshots/lab-1/user-check.png)

---
```cmd
Your turn

Run aws iam list-roles --output table. Floci may pre-create some service-linked roles. Are the results the same in text format? Which one would you use inside a script, and why?
```

![alt text](../../screenshots/lab-1/user-role.png)

No the result is not same in the text format because the --output table shows the result in borders (+---, |) and the text shows plain text values without any headers or decoration. I will use the text format inside a script because of its parsing simplicity where it produces clean, tab-separated values

---

Created the three permission containers before creating any user, so users can be placed correctly. It is an empty IAM group and has no permissions and no members in the initial state. Moreover it is purely a container and it has no region because IAM is a global.

![alt text](../../screenshots/lab-1/group.png)

Verifying the group

![alt text](../../screenshots/lab-1/check-group.png)

Created the IAM users and capture their ARNs and learned that never copy an ID by hand because copying ARNs by hand from the screen into the next command is slow and error-prone. We can use the command instead 
```cmd 
ADMIN_ARN=$(aws iam create-user \
  --user-name usms-admin-01 \
  --tags Key=Project,Value=USMS Key=Role,Value=Administrator \
  --query 'User.Arn' \
  --output text)

DEV_ARN=$(aws iam create-user \
  --user-name usms-dev-01 \
  --tags Key=Project,Value=USMS Key=Role,Value=Developer \
  --query 'User.Arn' \
  --output text)

AUDIT_ARN=$(aws iam create-user \
  --user-name usms-audit-01 \
  --tags Key=Project,Value=USMS Key=Role,Value=Auditor \
  --query 'User.Arn' \
  --output text)

echo "$ADMIN_ARN"
echo "$DEV_ARN"
echo "$AUDIT_ARN"
```

![alt text](../../screenshots/lab-1/IAM-users.png)

verified that IAM users are created

![alt text](../../screenshots/lab-1/iamusercheck.png)

Inspected a single user and its tags

![alt text](../../screenshots/lab-1/user-detail.png)

---
```cmd
Your turn

Create a fourth user usms-intern-01, tagged Key=Role,Value=Intern, capturing its ARN into a variable named INTERN_ARN. Then display only the UserId of that user using get-user and --query.

Expected result:
An ARN ending in :user/usms-intern-01, and a UserId string starting with AIDA...
```
![alt text](../../screenshots/lab-1/new-user.png)

Added the users to group. It creates the membership link where it does not produces output at all on success because many AWS "action" commands are silent.

![alt text](../../screenshots/lab-1/group-user.png)

---

```cmd
Your turn

Put usms-intern-01 (from Step 19) into usms-auditors, then verify with a single command that the auditors group now has two members.

```
![alt text](../../screenshots/lab-1/user-group.png)

---

Exploring and attaching an AWS managed policy. AWS managed policies are maintained by AWS, shared across every account, and identified by ARNs where the account field is the literal word aws. ReadOnlyAccess is one of the rare cases where a managed policy is genuinely the right answer — an auditor really should be able to read everything and change nothing.

![alt text](../../screenshots/lab-1/policy.png)

Writing the first customer managed policy. 
The requirement, in plain English

A USMS developer must be able to look at the infrastructure (IAM, EC2, VPC, S3, CloudWatch), and build networking because Lab 2 is the VPC lab. They must not be able to create IAM users, delete anything permanent, or touch billing.

Checking the policies if it is valid or not

![alt text](../../screenshots/lab-1/policies.png)

![alt text](../../screenshots/lab-1/policies2.png)

![alt text](../../screenshots/lab-1/policies3.png)

Writing the S3 data policy.

![alt text](../../screenshots/lab-1/s3.png)

Using --generate-cli-skeleton to discover parameters to learn how to work out a command's parameters without leaving the terminal.

![alt text](../../screenshots/lab-1/cli.png)

---

```cmd
Your turn

Generate a skeleton for aws iam create-policy and for aws ec2 create-vpc (you will need the latter in Lab 2). Save both in templates/. Which parameter of create-vpc looks like the most important one?

```
![alt text](../../screenshots/lab-1/skeleton.png)

---

Adding an inline policy. The inline policy is embedded in a single identity. It has no ARN, cannot be attached elsewhere, and is deleted automatically when the identity is deleted. Use it when the permission is meaningful for exactly one identity and must never be reused by accident.

![alt text](../../screenshots/lab-1/inline-policies.png)


Reading everything about one user. Knowing a user's effective permissions you must check four places: group policies, attached user policies, inline user policies, and (in real AWS) permission boundaries and SCPs

![alt text](../../screenshots/lab-1/one-user.png)

Reading the actual policy JSON back out. where two calls are required: get-policy returns metadata, and only get-policy-version returns the document


![alt text](../../screenshots/lab-1/query.png)



Creating a role for EC2, with a trust policy. It is created the identity that the USMS application server will use in Lab 3 and understand why servers must never hold access keys.

![alt text](../../screenshots/lab-1/EC2.png)

Created the instance profile where an EC2 instance cannot be given a role directly. It is given an instance profile, which is a thin wrapper containing exactly one role. 

![alt text](../../screenshots/lab-1/EC22.png)

Giving the developers group permission to assume it

![alt text](../../screenshots/lab-1/role.png)

Policy versions where customer managed policies keep up to 5 versions, so you can roll back.

![alt text](../../screenshots/lab-1/policie-version.png)

Confirming if Git is protecting the repo.

![alt text](../../screenshots/lab-1/git-save.png)

```cmd
Your turn

Predict — before running anything — the decision for usms-audit-01 on ec2:CreateVpc and on ec2:DescribeVpcs. Write your prediction in notes/lab-01-notes.md, then check it. If Floci does not support the simulator, justify your prediction by quoting the relevant statement from the policy JSON.
```
![alt text](../../screenshots/lab-1/spp.png)

---

Commited the work

![alt text](../../screenshots/lab-1/commit.png)

Verification

![alt text](../../screenshots/lab-1/v.png)

