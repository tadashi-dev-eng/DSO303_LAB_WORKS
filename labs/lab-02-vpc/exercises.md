For the lab 2 we need to check the set up and found that the prerequistes not present

![alt text](../../screenshots/Lab-2/lab2-Prerequisites.png)

To solve the issue I follwed the folowing step. 

1. opended the nano ~/.bashrc and looked for the sources configs/course.env 

![alt text](../../screenshots/Lab-2/nano.png)

2. Reloaded the shell configuration and verified the output again 

![alt text](../../screenshots/Lab-2/nano2.png)

In this Lab 2 we are trying to build the University student management system that has ``web tire`` where a students and staff can reach through internet, ``data tire`` that holds transcripts and enrolment records that can never be reachable from the internet. Plus the requirement the data tire can fetch operating system updates outbound. 

## Step 1 Resume the environment

Ensuring that the floci environemnt is running and using the persistent storage. 

![alt text](../../screenshots/Lab-2/floci-sh.png)

![alt text](../../screenshots/Lab-2/floci-sh2.png)

After running the commands, found that the everything is correctly configured and working. 

## Step 2 : Load the previous lab's environment and confirm your identity

This loads the key value created in the Lab1 and check the safety for target AWS account. 
It pulls the variables like developer role name, developer user and account ID by running lab-01.env and checks the target to make sure it is talking to the local emulator in ``000000000000`` at ``http://localhost:4566``

![alt text](../../screenshots/Lab-2/step2.png)

## Step 3 : Assume the developer role and create the VPC 

The first policy ``USMSDeveloperBase`` defines the minimum AWS service permissions required for developers to interact with application resources and prevent unauthorized access and ensures all developer execute under control. The json output shows the every ``Allowed`` or ``Deny`` action and resources assigned by the policy.

```cmd
tadashi@tadashi:~/Desktop/aws-floci-course$ echo "default version: $DEFAULT_VERSION"
default version: v3
tadashi@tadashi:~/Desktop/aws-floci-course$ aws iam get-policy-version \
  --policy-arn "$POLICY_ARN" \
  --version-id "$DEFAULT_VERSION" \
  --query 'PolicyVersion.Document' \
  --output json | tee outputs/lab-02-developer-base.json

{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ReadInfrastructure",
            "Effect": "Allow",
            "Action": [
                "iam:Get*",
                "iam:List*",
                "ec2:Describe*",
                "s3:List*",
                "s3:GetBucketLocation",
                "cloudwatch:Describe*",
                "cloudwatch:Get*",
                "logs:Describe*",
                "logs:GetLogEvents",
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        },
        {
            "Sid": "BuildNetworkingForLab02",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateVpc",
                "ec2:CreateSubnet",
                "ec2:CreateRouteTable",
                "ec2:CreateRoute",
                "ec2:CreateInternetGateway",
                "ec2:AttachInternetGateway",
                "ec2:AssociateRouteTable",
                "ec2:CreateSecurityGroup",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:CreateTags",
                "ec2:ModifyVpcAttribute",
                "ec2:DeleteVpc",
                "ec2:DescribeAvailabilityZones"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "us-east-1"
                }
            }
        },
        {
            "Sid": "DenyDangerousIdentityChanges",
            "Effect": "Deny",
            "Action": [
                "iam:CreateUser",
                "iam:DeleteUser",
                "iam:CreateAccessKey",
                "iam:AttachUserPolicy",
                "iam:PutUserPolicy",
                "aws-portal:*",
                "organizations:*"
            ],
            "Resource": "*"
        }
    ]
}
tadashi@tadashi:~/Desktop/aws-floci-course$ 
```

## Assumming the role

Here I performed the temporary security credentials assumption through : 
1. Calling the aws security token service ( STS ) to request temporary access credentials (Access Key, Secret Key, and Session Token) for the role specified in $ROLE_ARN.
2. Saves the STS response containing the temporary credentials into a local file in ``outputs/lab-02-assumed-role.json``
3. Sets strict file permissions so only your local Linux user can read or write the credentials file by ``chmod 600 outputs/lab-02-assumed-role.json``
4. Confirms that your active shell identity has successfully changed from the base user to the assumed role context by ``aws sts get-caller-identity``

![alt text](../../screenshots/Lab-2/A1.png)


![alt text](../../screenshots/Lab-2/A2.png)

## Creating the VPC

Creating the VPC uses the /16 IPv4 address. 
1. It calls the Amazon Elastic Compute Cloud APIs, which govern core networking primitives in addition to compute instances. 
2. Allocates a contiguous private address space of 65,536 total IPv4 addresses (10.0.0.0 to 10.0.255.255). 
3. Applies four key metadata tags (Name, Project, Tier, ManagedBy) in the same single API call as resource creation.

![alt text](../../screenshots/Lab-2/vpc.png)

## Step 4 Restore your normal identity

``usms-developer-role`` was created with a one-hour maximum session duration, these credentials will expire later in the lab so to prevent this it revokes the temporary session credentials assumed role by : 
1. Removing the temporary IAM role credentials from your terminal's environment variables.
2. Confirms your active caller identity has reverted back to the baseline identity ( arn:aws:iam::000000000000:root )

![alt text](../../screenshots/Lab-2/restore.png)

## Step 5 Enable DNS support and DNS hostnames



