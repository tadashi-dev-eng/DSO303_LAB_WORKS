## 1. Aim / Objective

## 2. Introduction

## 3. Use Case

## 4. System Architecture / Design


## 5. Implementation Procedure

###  Resume Environment & Verify Network

1. Environment Setup & Verification: Loaded environment variables from Lab 01 (configs/lab-01.env) and Lab 02 (configs/lab-02.env), then confirmed that the custom VPC, public subnet, private subnet, and security groups were intact.

2. Key Pair Creation: Generated a dedicated SSH key pair (lab-03-key), saved the private key to keys/lab-03-key.pem, updated file permissions to 400 (read-only by owner), and verified entry in .gitignore.

3. User Data Scripting: Created a bootstrap script (scripts/user-data.sh) to automatically update packages, install Apache HTTP Server (httpd), start the service, and write a custom landing page for USMS.

4. Public Web Server Launch: Provisioned a t2.micro EC2 instance in the public subnet with the user-data script attached and tagged as USMS-Web-Server.

5. Elastic IP Allocation & Attachment: Allocated an Elastic IP address and associated it with the running web instance to ensure a static public entry point.

6. EBS Volume Attachment: Created a 10 GiB General Purpose SSD (gp2) EBS volume in the web instance’s Availability Zone and attached it as /dev/xvdf.

7. Private DB Tier Launch: Provisioned a second t2.micro EC2 instance inside the private subnet tagged as USMS-DB-Server using the private security group.

8. Gold Image Creation: Created a custom Amazon Machine Image (AMI) named USMS-Web-Server-AMI from the configured web instance.

9. Environment Configuration & Automation: Exported resource identifiers to configs/lab-03.env, committed changes to Git, and executed an automated verification script (scripts/utilities/verify-lab-03.sh).


## 6. Results and Evidence

### Step 1 - Resume the environment and load three env files

it re-establishes the terminal context by loading stored variables from Lab 01 (configs/lab-01.env) and Lab 02 (configs/lab-02.env). However i have to ensure that all the previously defined environment variables—such as VPC_ID, PUBLIC_SUBNET_ID, PRIVATE_SUBNET_ID, PUBLIC_SG_ID, and PRIVATE_SG_ID are actively loaded into the active shell session.

![alt text](../../screenshots/Lab-3/step1.png)

### Step 2 - Confirm Lab 02's network is intact
