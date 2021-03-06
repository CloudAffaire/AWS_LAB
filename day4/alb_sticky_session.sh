#################################################
## Sticky Session In Application Load Balancer ##
#################################################

##----------------------------------
## Create custom vpc for your alb ##
##----------------------------------
## Create a directory for this demo
mkdir aws_alb_sticky_session_demo && cd aws_alb_sticky_session_demo

## Create a VPC with DNS hostname enabled
AWS_VPC_ID=$(aws ec2 create-vpc \
--cidr-block 10.0.0.0/16 \
--query 'Vpc.{VpcId:VpcId}' \
--output text) &&
aws ec2 modify-vpc-attribute \
--vpc-id $AWS_VPC_ID \
--enable-dns-hostnames "{\"Value\":true}"

## Create two public subnets
AWS_SUBNET_PUBLIC_ONE_ID=$(aws ec2 create-subnet \
--vpc-id $AWS_VPC_ID --cidr-block 10.0.1.0/24 \
--availability-zone ap-south-1a --query 'Subnet.{SubnetId:SubnetId}' \
--output text) &&
AWS_SUBNET_PUBLIC_TWO_ID=$(aws ec2 create-subnet \
--vpc-id $AWS_VPC_ID --cidr-block 10.0.2.0/24 \
--availability-zone ap-south-1b --query 'Subnet.{SubnetId:SubnetId}' \
--output text) &&
aws ec2 modify-subnet-attribute \
  --subnet-id $AWS_SUBNET_PUBLIC_ONE_ID \
  --map-public-ip-on-launch &&
aws ec2 modify-subnet-attribute \
  --subnet-id $AWS_SUBNET_PUBLIC_TWO_ID \
  --map-public-ip-on-launch

## Create an Internet Gateway
AWS_INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway \
--query 'InternetGateway.{InternetGatewayId:InternetGatewayId}' \
--output text) &&
aws ec2 attach-internet-gateway \
--vpc-id $AWS_VPC_ID \
--internet-gateway-id $AWS_INTERNET_GATEWAY_ID

## Create a route table
AWS_CUSTOM_ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id $AWS_VPC_ID \
  --query 'RouteTable.{RouteTableId:RouteTableId}' \
  --output text ) &&
aws ec2 create-route \
--route-table-id $AWS_CUSTOM_ROUTE_TABLE_ID \
--destination-cidr-block 0.0.0.0/0 \
--gateway-id $AWS_INTERNET_GATEWAY_ID

## Associate the public subnet with route table
AWS_ROUTE_TABLE_ASSOID_ONE=$(aws ec2 associate-route-table  \
--subnet-id $AWS_SUBNET_PUBLIC_ONE_ID \
--route-table-id $AWS_CUSTOM_ROUTE_TABLE_ID \
--query 'AssociationId' \
--output text) &&
AWS_ROUTE_TABLE_ASSOID_TWO=$(aws ec2 associate-route-table  \
--subnet-id $AWS_SUBNET_PUBLIC_TWO_ID \
--route-table-id $AWS_CUSTOM_ROUTE_TABLE_ID \
--query 'AssociationId' \
--output text)

## Create a security group
aws ec2 create-security-group \
--vpc-id $AWS_VPC_ID \
--group-name myvpc-security-group \
--description 'My VPC non default security group'

## Get security group ID's
AWS_DEFAULT_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
--filters "Name=vpc-id,Values=$AWS_VPC_ID" \
--query 'SecurityGroups[?GroupName == `default`].GroupId' \
--output text) &&
AWS_CUSTOM_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
--filters "Name=vpc-id,Values=$AWS_VPC_ID" \
--query 'SecurityGroups[?GroupName == `myvpc-security-group`].GroupId' \
--output text)

## Create security group ingress rules
aws ec2 authorize-security-group-ingress \
--group-id $AWS_CUSTOM_SECURITY_GROUP_ID \
--ip-permissions '[{"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow SSH"}]}]' &&
aws ec2 authorize-security-group-ingress \
--group-id $AWS_CUSTOM_SECURITY_GROUP_ID \
--ip-permissions '[{"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80, "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow HTTP"}]}]'

##--------------------------------------------------
## Create two ec2 instances your alb target group ##
##--------------------------------------------------

## Get Amazon Linux 2 latest AMI ID
AWS_AMI_ID=$(aws ec2 describe-images \
--owners 'amazon' \
--filters 'Name=name,Values=amzn2-ami-hvm-2.0.????????-x86_64-gp2' 'Name=state,Values=available' \
--query 'sort_by(Images, &CreationDate)[-1].[ImageId]' \
--output 'text')

## Create a key-pair
aws ec2 create-key-pair \
--key-name myvpc-keypair \
--query 'KeyMaterial' \
--output text > myvpc-keypair.pem &&
chmod 400 myvpc-keypair.pem

## Create user data to configure LAMP stack
vi myuserdataone.txt
-----------------------
#!/bin/bash
sudo yum install -y httpd
sudo systemctl start httpd
sudo usermod -a -G apache ec2-user
sudo chown -R ec2-user:apache /var/www
sudo chmod 2775 /var/www
sudo find /var/www -type d -exec chmod 2775 {} \;
sudo find /var/www -type f -exec chmod 0664 {} \;
sudo echo "hello from instance one" > /var/www/html/index.html
-----------------------
:wq

vi myuserdatatwo.txt
-----------------------
#!/bin/bash
sudo yum install -y httpd
sudo systemctl start httpd
sudo usermod -a -G apache ec2-user
sudo chown -R ec2-user:apache /var/www
sudo chmod 2775 /var/www
sudo find /var/www -type d -exec chmod 2775 {} \;
sudo find /var/www -type f -exec chmod 0664 {} \;
sudo echo "hello from instance two" > /var/www/html/index.html
-----------------------
:wq

## Create two EC2 instance in two public subnet
AWS_EC2_INSTANCE_ONE_ID=$(aws ec2 run-instances \
--image-id $AWS_AMI_ID \
--instance-type t2.micro \
--key-name myvpc-keypair \
--monitoring "Enabled=false" \
--security-group-ids $AWS_CUSTOM_SECURITY_GROUP_ID \
--subnet-id $AWS_SUBNET_PUBLIC_ONE_ID \
--user-data file://myuserdataone.txt \
--private-ip-address 10.0.1.10 \
--query 'Instances[0].InstanceId' \
--output text) &&
AWS_EC2_INSTANCE_TWO_ID=$(aws ec2 run-instances \
--image-id $AWS_AMI_ID \
--instance-type t2.micro \
--key-name myvpc-keypair \
--monitoring "Enabled=false" \
--security-group-ids $AWS_CUSTOM_SECURITY_GROUP_ID \
--subnet-id $AWS_SUBNET_PUBLIC_TWO_ID \
--user-data file://myuserdatatwo.txt \
--private-ip-address 10.0.2.10 \
--query 'Instances[0].InstanceId' \
--output text)

##------------------------------------
## Create application load balancer ##
##------------------------------------

## Create the application load balancer
AWS_ALB_ARN=$(aws elbv2 create-load-balancer \
--name my-application-load-balancer  \
--subnets $AWS_SUBNET_PUBLIC_ONE_ID $AWS_SUBNET_PUBLIC_TWO_ID \
--security-groups $AWS_CUSTOM_SECURITY_GROUP_ID \
--query 'LoadBalancers[0].LoadBalancerArn' \
--output text)

## Check the status of load balancer
aws elbv2 describe-load-balancers \
--load-balancer-arns $AWS_ALB_ARN \
--query 'LoadBalancers[0].State.Code' \
--output text

## Once the ALB status is active, get the DNS name for your ALB
AWS_ALB_DNS=$(aws elbv2 describe-load-balancers \
--load-balancer-arns $AWS_ALB_ARN \
--query 'LoadBalancers[0].DNSName' \
--output text) &&
echo $AWS_ALB_DNS

## Create the target group for your ALB
AWS_ALB_TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
--name my-alb-targets \
--protocol HTTP --port 80 \
--vpc-id $AWS_VPC_ID \
--query 'TargetGroups[0].TargetGroupArn' \
--output text)

## Register both the instances in the target group
aws elbv2 register-targets --target-group-arn $AWS_ALB_TARGET_GROUP_ARN  \
--targets Id=$AWS_EC2_INSTANCE_ONE_ID Id=$AWS_EC2_INSTANCE_TWO_ID

## Create a listener for your load balancer with a default rule that forwards requests to your target group
AWS_ALB_LISTNER_ARN=$(aws elbv2 create-listener --load-balancer-arn $AWS_ALB_ARN \
--protocol HTTP --port 80  \
--default-actions Type=forward,TargetGroupArn=$AWS_ALB_TARGET_GROUP_ARN \
--query 'Listeners[0].ListenerArn' \
--output text)

## Verify the health of the registered targets for your target group
aws elbv2 describe-target-health --target-group-arn $AWS_ALB_TARGET_GROUP_ARN

##-------------------------------------
## Configure Sticky Sessions For ALB ##
##-------------------------------------

## Open the DNS name of your ALB (below output) in your browser and hit refresh several time
echo $AWS_ALB_DNS

## Responce from both the instances

## Check current configuration
aws elbv2 describe-target-group-attributes \
--target-group-arn $AWS_ALB_TARGET_GROUP_ARN

## Enable Sticky Session
aws elbv2 modify-target-group-attributes \
--target-group-arn $AWS_ALB_TARGET_GROUP_ARN \
--attributes Key=stickiness.enabled,Value=true Key=stickiness.lb_cookie.duration_seconds,Value=60

## Open the DNS name of your ALB (below output) in your browser and hit refresh several time
echo $AWS_ALB_DNS

## Responce from only one instance for 60 seconds

## Disable Sticky Session
aws elbv2 modify-target-group-attributes \
--target-group-arn $AWS_ALB_TARGET_GROUP_ARN \
--attributes Key=stickiness.enabled,Value=false 

## Open the DNS name of your ALB (below output) in your browser and hit refresh several time
echo $AWS_ALB_DNS

## Responce from both the instances
  
##-----------
## Cleanup ##
##-----------

## Delete the listener
aws elbv2 delete-listener \
--listener-arn $AWS_ALB_LISTNER_ARN

## Deregister targets
aws elbv2 deregister-targets \
--target-group-arn $AWS_ALB_TARGET_GROUP_ARN \
--targets Id=$AWS_EC2_INSTANCE_ONE_ID Id=$AWS_EC2_INSTANCE_TWO_ID

## Delete target group
aws elbv2 delete-target-group \
--target-group-arn $AWS_ALB_TARGET_GROUP_ARN

## Delete Application Load Balancer
aws elbv2 delete-load-balancer \
--load-balancer-arn $AWS_ALB_ARN

## Terminate the ec2 instances
aws ec2 terminate-instances \
--instance-ids $AWS_EC2_INSTANCE_ONE_ID &&
rm -f myuserdataone.txt

aws ec2 terminate-instances \
--instance-ids $AWS_EC2_INSTANCE_TWO_ID &&
rm -f myuserdatatwo.txt

## Delete key pair
aws ec2 delete-key-pair \
--key-name myvpc-keypair &&
rm -f myvpc-keypair.pem

## Delete custom security group (once instances are terminated)
aws ec2 delete-security-group \
--group-id $AWS_CUSTOM_SECURITY_GROUP_ID

## Delete internet gateway
aws ec2 detach-internet-gateway \
--internet-gateway-id $AWS_INTERNET_GATEWAY_ID \
--vpc-id $AWS_VPC_ID &&
aws ec2 delete-internet-gateway \
--internet-gateway-id $AWS_INTERNET_GATEWAY_ID

## Disassociate the subnets from custom route table
aws ec2 disassociate-route-table \
--association-id $AWS_ROUTE_TABLE_ASSOID_ONE &&
aws ec2 disassociate-route-table \
--association-id $AWS_ROUTE_TABLE_ASSOID_TWO

## Delete custom route table
aws ec2 delete-route-table \
--route-table-id $AWS_CUSTOM_ROUTE_TABLE_ID

## Delete the public subnets
aws ec2 delete-subnet \
--subnet-id $AWS_SUBNET_PUBLIC_ONE_ID &&
aws ec2 delete-subnet \
--subnet-id $AWS_SUBNET_PUBLIC_TWO_ID

## Delete the vpc
aws ec2 delete-vpc \
--vpc-id $AWS_VPC_ID

## Delete the directory used for this demo
cd .. && rm -rf aws_alb_sticky_session_demo
