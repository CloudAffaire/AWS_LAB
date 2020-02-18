
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
--output text > myvpc-keypair.pem

## Create user data for a LAMP stack
vi myuserdata.txt
-----------------------
#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
sudo yum install -y httpd mariadb-server
sudo systemctl start httpd
sudo systemctl is-enabled httpd
-----------------------
:wq

## Create an EC2 instance
AWS_EC2_INSTANCE_ID=$(aws ec2 run-instances \
--image-id $AWS_AMI_ID \
--instance-type t2.micro \
--key-name myvpc-keypair \
--monitoring "Enabled=false" \
--security-group-ids $AWS_CUSTOM_SECURITY_GROUP_ID \
--subnet-id $AWS_SUBNET_PUBLIC_ID \
--user-data file://myuserdata.txt \
--private-ip-address 10.0.1.10 \
--query 'Instances[0].InstanceId' \
--output text)

## Add a tag to the ec2 instance  
aws ec2 create-tags \
--resources $AWS_EC2_INSTANCE_ID \
--tags "Key=Name,Value=myvpc-ec2-instance"

## Check if the instance is running
aws ec2 describe-instance-status \
--instance-ids $AWS_EC2_INSTANCE_ID --output text

## Get the public ip address of your instance
AWS_EC2_INSTANCE_PUBLIC_IP=$(aws ec2 describe-instances \
  --query "Reservations[*].Instances[*].PublicIpAddress" \
  --output=text) &&
echo $AWS_EC2_INSTANCE_PUBLIC_IP

## Try to connect to the instance
chmod 400 myvpc-keypair.pem
ssh -i myvpc-keypair.pem ec2-user@$AWS_EC2_INSTANCE_PUBLIC_IP
exit

## Open browser and type the public ip address of your ec2 instance

## Cleanup
## Terminate the ec2 instance
aws ec2 terminate-instances \
--instance-ids $AWS_EC2_INSTANCE_ID &&
rm -f myuserdata.txt

## Delete key pair
aws ec2 delete-key-pair \
--key-name myvpc-keypair &&
rm -f myvpc-keypair.pem

## Delete custom security group
aws ec2 delete-security-group \
--group-id $AWS_CUSTOM_SECURITY_GROUP_ID

## Delete internet gateway
aws ec2 detach-internet-gateway \
--internet-gateway-id $AWS_INTERNET_GATEWAY_ID \
--vpc-id $AWS_VPC_ID &&
aws ec2 delete-internet-gateway \
--internet-gateway-id $AWS_INTERNET_GATEWAY_ID

## Delete the custom route table
aws ec2 disassociate-route-table \
--association-id $AWS_ROUTE_TABLE_ASSOID &&
aws ec2 delete-route-table \
--route-table-id $AWS_CUSTOM_ROUTE_TABLE_ID

## Delete the public subnet
aws ec2 delete-subnet \
--subnet-id $AWS_SUBNET_PUBLIC_ID

## Delete the vpc
aws ec2 delete-vpc \
--vpc-id $AWS_VPC_ID
