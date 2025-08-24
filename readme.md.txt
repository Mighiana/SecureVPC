SecureVPC Project
Overview
This project sets up a secure AWS Virtual Private Cloud (VPC) named securevpc-usman in the us-east-1 region (account ID 505679504699). The VPC includes a public subnet hosting a Bastion Host for SSH access, a private subnet hosting a Web Server, and VPC Flow Logs to monitor network traffic. Security is enforced through Security Groups and Network ACLs (NACLs), ensuring only authorized access (SSH to Bastion Host from a specific IP, SSH and HTTP to Web Server from Bastion Host, and blocking external access to the Web Server).
Architecture

VPC: securevpc-usman (e.g., vpc-12345678, CIDR 10.0.0.0/16)
Subnets:
PublicSubnet: 10.0.1.0/24 (hosts BastionHost)
PrivateSubnet: 10.0.2.0/24 (hosts WebServer)


Internet Gateway: Attached to VPC for public subnet internet access
NAT Gateway: In PublicSubnet for PrivateSubnet outbound traffic
EC2 Instances:
BastionHost: Amazon Linux 2, t2.micro, private IP 10.0.1.139, public IP 3.227.20.88, Security Group BastionSG
WebServer: Amazon Linux 2, t2.micro, private IP 10.0.2.164, no public IP, Security Group WebServerSG


Security Groups:
BastionSG: Allows SSH (port 22) from <your-ip>/32 (e.g., 203.0.113.1/32 or 45.45.224.90/32)
WebServerSG: Allows SSH (port 22) and HTTP (port 80) from BastionSG


NACLs:
PublicSubnet: Allows inbound SSH (port 22) from <your-ip>/32, ephemeral ports; outbound to 10.0.2.0/24 and <your-ip>/32
PrivateSubnet: Allows inbound SSH (port 22) and HTTP (port 80) from 10.0.1.0/24, ephemeral ports; outbound to 10.0.1.0/24 and 0.0.0.0/0


Flow Logs: Captures all VPC traffic to CloudWatch log group /aws/vpc/SecureVPC-FlowLogs using IAM role VPCFlowLogsRole
Key Pair: SecureVPC-Key (private key SecureVPC-Key.pem stored in C:\Users\usman\.ssh)

Setup Instructions
Step 1: Create VPC and Networking

In the AWS Management Console, go to VPC > Your VPCs > Create VPC.
Name: securevpc-usman
IPv4 CIDR: 10.0.0.0/16


Create subnets:
PublicSubnet: Name PublicSubnet, CIDR 10.0.1.0/24, Availability Zone us-east-1a
PrivateSubnet: Name PrivateSubnet, CIDR 10.0.2.0/24, Availability Zone us-east-1a


Create and attach an Internet Gateway to securevpc-usman.
Create a NAT Gateway in PublicSubnet with an Elastic IP.
Update route tables:
Public Route Table: Route 0.0.0.0/0 to Internet Gateway, associate with PublicSubnet.
Private Route Table: Route 0.0.0.0/0 to NAT Gateway, associate with PrivateSubnet.



Step 2: Launch EC2 Instances

Go to EC2 > Instances > Launch instances.
BastionHost:
Name: BastionHost
AMI: Amazon Linux 2 AMI (HVM)
Instance type: t2.micro
Key pair: SecureVPC-Key
Network: VPC securevpc-usman, Subnet PublicSubnet, Auto-assign public IP: Enable
Security Group: Select BastionSG (create in Step 3)


WebServer:
Name: WebServer
AMI: Amazon Linux 2 AMI (HVM)
Instance type: t2.micro
Key pair: SecureVPC-Key
Network: VPC securevpc-usman, Subnet PrivateSubnet, Auto-assign public IP: Disable
Security Group: Select WebServerSG (create in Step 3)
User data:#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Secure Web Server</h1>" > /var/www/html/index.html





Step 3: Configure Security Groups

Go to EC2 > Security Groups > Create security group.
BastionSG:
Name: BastionSG
Description: “Security Group for Bastion Host”
VPC: securevpc-usman
Inbound: TCP, port 22, source <your-ip>/32 (find your IP at https://www.whatismyip.com)
Outbound: All traffic (0.0.0.0/0)


WebServerSG:
Name: WebServerSG
Description: “Security Group for Web Server”
VPC: securevpc-usman
Inbound: TCP, port 22 and 80, source BastionSG (select Security Group ID)
Outbound: All traffic (0.0.0.0/0)


Attach to instances:
BastionHost: Assign BastionSG
WebServer: Assign WebServerSG



Step 4: Configure NACLs

Go to VPC > Network ACLs.
PublicSubnet NACL:
Inbound:
Rule 100: TCP, port 22, source <your-ip>/32, Allow
Rule 200: TCP, ports 1024–65535, source 0.0.0.0/0, Allow


Outbound:
Rule 100: TCP, ports 1024–65535, source <your-ip>/32, Allow
Rule 200: All traffic, destination 10.0.2.0/24, Allow




PrivateSubnet NACL:
Inbound:
Rule 100: TCP, ports 22 and 80, source 10.0.1.0/24, Allow
Rule 200: TCP, ports 1024–65535, source 10.0.1.0/24, Allow


Outbound:
Rule 100: TCP, ports 1024–65535, destination 10.0.1.0/24, Allow
Rule 200: All traffic, destination 0.0.0.0/0, Allow





Step 5: Enable VPC Flow Logs

Create IAM policy VPCFlowLogsPolicy:
Go to IAM > Policies > Create policy.
JSON:{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ],
            "Resource": "*"
        }
    ]
}


Name: VPCFlowLogsPolicy


Create IAM role VPCFlowLogsRole:
Go to IAM > Roles > Create role.
Trusted entity: AWS service, VPC Flow Logs.
Attach policy: VPCFlowLogsPolicy.


Enable Flow Logs:
Go to VPC > Your VPCs > select securevpc-usman > Flow Logs > Create flow log.
Name: SecureVPC-FlowLogs
Filter: All
Destination: CloudWatch Logs, log group /aws/vpc/SecureVPC-FlowLogs
IAM role: VPCFlowLogsRole



Step 6: Test Connectivity

SSH to Bastion Host:
From your local machine (Windows, C:\Users\usman):ssh -i C:\Users\usman\.ssh\SecureVPC-Key.pem ec2-user@3.227.20.88




Copy SSH Key to Bastion Host (if needed):
From local machine:scp -i C:\Users\usman\.ssh\SecureVPC-Key.pem C:\Users\usman\.ssh\SecureVPC-Key.pem ec2-user@3.227.20.88:/home/ec2-user/.ssh/SecureVPC-Key.pem


On BastionHost:chmod 400 ~/.ssh/SecureVPC-Key.pem




SSH to Web Server:
From BastionHost:ssh -i ~/.ssh/SecureVPC-Key.pem ec2-user@10.0.2.164




Test HTTP to Web Server:
From BastionHost:curl http://10.0.2.164


Expected: <h1>Secure Web Server</h1>




Test Web Server Inaccessibility:
From local machine:curl http://10.0.2.164


Expected: Connection fails (private IP, blocked by WebServerSG).





Step 7: Analyze Flow Logs

Go to CloudWatch > Log groups > /aws/vpc/SecureVPC-FlowLogs > Logs Insights.
Run:fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, protocol, action, status
| sort @timestamp desc
| limit 50


Expected:
SSH to BastionHost: srcAddr=<your-ip>, dstAddr=10.0.1.139, dstPort=22, action=ACCEPT
SSH to WebServer: srcAddr=10.0.1.139, dstAddr=10.0.2.164, dstPort=22, action=ACCEPT
HTTP to WebServer: srcAddr=10.0.1.139, dstAddr=10.0.2.164, dstPort=80, action=ACCEPT
Rejected access: dstAddr=10.0.1.139 or 10.0.2.164, action=REJECT



Troubleshooting

No ACCEPT Entries in Flow Logs:
Verify Security Groups: BastionSG (port 22, <your-ip>/32), WebServerSG (ports 22, 80, BastionSG).
Verify NACLs: Allow appropriate ports (22, 80, ephemeral).
Check instance status: Ensure BastionHost and WebServer are running.
Fix SSH to WebServer:
Use EC2 Instance Connect to add public key to ~/.ssh/authorized_keys:echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDe7rmhtuMjdzQIX11ZSQ+ITdEKW3YYh+YFH+2rBUk727IYNOnoI9F4Ejw3KjgWZvdtygDsEa3cEHEFeElMrO4jacogrAuqcfkuO9+epHyGn4f1hdeox71Ok8gf2CtylP5p8ba++QESMtTYwRccQDzjvePeugh1GUlVBo9leC7PykryTQt2xrOVdakVQJYy1CaJ9u5f6MJRJDsbmQtyL1equ58e6nRMfF5N96cUnyJu3PZA05ZbkA9CKvu7xgtkANRDEvhWBvyPj6DAOoiuahOHMGdOZ37+BpsHyXMCib+A4XgVwXvzyudlFFmTU1Ji6c9N8v13GQ/Bgw1+4ogjhWhF" >> ~/.ssh/authorized_keys


Or recreate WebServer with correct key pair (SecureVPC-Key).





Notes

Replace <your-ip> with your public IP (find at https://www.whatismyip.com).
If WebServer IP changes after recreation, update tests with the new IP.
Flow Logs may take 5–10 minutes to capture traffic.
