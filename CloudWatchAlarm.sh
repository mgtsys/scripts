#!/bin/bash

##Check the AWS binares and AWS Configure command is setup.
AwsCliCheck(){
AwsBinaryCheck=$(type aws 2>&1)
if   ! [[ "$AwsBinaryCheck" =~ "bin" ]];then
   echo -ne "\n\e[31m Error: Please install aws-cli and configure AWS Access keys\e[00m\n"
   exit
fi
if ! [ -f "$HOME/.aws/config" ] || ! [ -f "$HOME/.aws/credentials" ] ;then
   echo -ne "\n\e[31m Error: Please configure the AWS Access Keys and Region with aws configure command\e[00m\n"
   exit	
fi
}

##User Input Topic Name
User_Input(){
echo -ne "\nEnter the SNS Topic Name: "
read TopicName
}

##Create and Verify the Topic Name
Create_And_Verify_TopicName(){
TopicARN=$(aws sns create-topic --name $TopicName 2>&1)

##Verify the Topic Name is in correct format or exit
if [[ "$TopicARN" == *"InvalidParameter"* ]];then
  echo -ne "\n\e[31m Error: The Topic Name must be maximum 256 characters. Can include alphanumeric characters, hyphens (-) and underscores (_).\e[00m\n"
  exit
else   
 echo -ne "Enter the email address to receive Alert Notifications: "
 read emailID
fi
}


##Create and Verify Email Subcription
Create_And_Verify_Subcription(){
Subscribe=$(aws sns subscribe --topic-arn $TopicARN --protocol email --notification-endpoint $emailID 2>&1)

##Verify the Email ID is correct
if [[ "$Subscribe" == *"InvalidParameter"* ]];then
echo -ne "\n\e[31mError: The Email address is not valid, please verify it again.\e[00m\n"

##Deleting TopicName if Email ID verification failed	
echo -ne "\n\e[33m Deleting the Topic created $TopicName....\e[00m\n"
aws sns delete-topic --topic-arn $TopicARN 
sleep 2

##Verify if the Topic Name has been deleted
TopicList=$(aws sns list-topics 2>&1) 
if ! [[ "$TopicList" =~ "$TopicName" ]];then
   echo -ne "\n\e[32m The Topic Name $TopicName is successfully deleted\e[00m \n"	  
   exit
else
   echo -ne "\n\e[31m Error: Please login in the Console to delete it Manually\e[00m \n"	   
exit 
fi
else
  echo -ne "\n\e[32m The email address $emailID is added succesfully.\e[00m "
  echo -ne "\n\e[32m Pending Confirmation from the customer to activate the subcription.\e[00m\n"	
fi	
}


##User Input to add addtional emails
User_Input_Email(){
echo -ne "\n Do you want to add another email ID ( Yes/No ): "
read option
}

##Add Addtional Email ID to the same Topic/Subcription
Add_Additional_Email(){
if [[ "$option" == "Yes" ]];then
echo -ne "\nEnter the email address to receive Alert Notifications: "
read emailID2 	

##Subcribe the Email ID to the Topic Name via AWS
Subscribe2=$(aws sns subscribe --topic-arn $TopicARN --protocol email --notification-endpoint $emailID2 2>&1)
if [[ "$Subscribe2" == *"InvalidParameter"* ]];then
     echo -ne "\n\e[31m Error: Email address not valid, please verify it again.\e[00m\n"
     exit
else     
     echo -ne "\n\e[32m The email address $emailID2 is added succesfully.\e[00m "
     echo -ne "\n\e[32m Pending Confirmation from the customer to activate the subcription.\e[00m\n"	 
Add_Multiple_Emails
fi
else
if [[ "$option" == "No" ]];then
   Option_Select
else
   echo -ne "\n\e[31m Error: Input Allowed Yes or No\e[00m\n"
   Add_Multiple_Emails   
fi
fi
}

##Select the Desired Metric to Configure Alarm
Option_Select(){

echo -ne "\nPlease choose the Appropriate Options for the desired output  \n"

echo -ne "\n 1) Enter 1 to configure High CPU Utilizations Alarm"
echo -ne "\n 2) Enter 2 to configure High Memory Utilizations Alarm\n"

echo -ne "\n Enter your option: "
read option

if   [[ "$option" == "1" ]];then
   CPU_Utilization
elif [[ "$option" == "2" ]];then
   MEM_Utilization
else
   echo -ne "\n\e[31m Error: Please select option (1 to 2) for the desired output\e[00m\n"
fi
}


##User Input and Create CPU Alarm
CPU_Utilization() {

echo -ne "\n1) Enter the Instance ID to monitor: "
read instanceid

CheckID=$(aws ec2 describe-instances --instance-id $instanceid 2>&1)

if [[ "$CheckID" == *"InvalidInstanceID.Malformed"*  ]];then
   echo -ne "\n\e[31m Error: Please make sure the Instance ID is correct\e[00m\n"
   exit
fi

echo -ne "2) Enter the Threshold value, whenever the CPU Utilization is Greater/Equal than... : " 
read threshold	

INT=^[0-9]+$

if ! [[ $threshold =~ $INT ]];then
  echo -ne "\n\e[31m Error: Please Enter Number only \e[00m\n"
  exit
fi  

echo -ne "3) Enter the Alarm Name: "
read alarmname

CPU_Alarm_Output=$(aws cloudwatch put-metric-alarm --alarm-name $alarmname --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 300 --threshold $threshold --comparison-operator GreaterThanOrEqualToThreshold --dimensions "Name=InstanceId,Value=$instanceid" --evaluation-periods 1 --alarm-actions $TopicARN --unit Percent 2>&1)

if [[ "$CPU_Alarm_Output" == *"InvalidParameter"* ]];then
  echo -ne "\n\e[31mError: $CPU_Alarm_Output\e[00m\n"
  exit
else     
  echo -ne "\n\e[32m The $alarmname is created succesfully!!!\e[00m \n"
fi
}

##Memory Utilization
MEM_Utilization(){

echo -ne "\n\e[33m PLEASE MAKE SURE THE CLOUD WATCH AGENT IS CONFIUGRED FOR THE MEMORY MONITORING\e[00m\n"	

echo -ne "\n1)Enter the Instance ID to monitor: "
read instanceid

CheckID=$(aws ec2 describe-instances --instance-id $instanceid 2>&1)
if [[ "$CheckID" == *"InvalidInstanceID.Malformed"*  ]];then
   echo -ne "\n\e[31m Error: Please make sure the Instance ID is correct\e[00m\n"
exit
fi

echo -ne "2)Enter the Threshold value, whenever the Memory Utilization is Greater/Equal than... : " 
read threshold	

INT=^[0-9]+$
if ! [[ $threshold =~ $INT ]];then
  echo -ne "\n\e[31m Error: Please Enter Number only \e[00m\n"
exit
fi  

echo -ne "3)Enter the Alarm Name: "
read alarmname

##Fetch InstanceType & ImageID
InstanceMetaData=$(aws ec2 describe-instances --instance-id $instanceid --output json 2>&1)
ImageId=$(echo $InstanceMetaData | awk -F '"' '{print $12}')
InstanceType=$(echo $InstanceMetaData | awk -F '"' '{print $20}')

MEM_Alarm_Output=$(aws cloudwatch put-metric-alarm --alarm-name $alarmname --metric-name mem_used_percent --namespace CWAgent --statistic Average --period 300 --threshold $threshold --comparison-operator GreaterThanOrEqualToThreshold --dimensions Name=InstanceId,Value=$instanceid Name=ImageId,Value=$ImageId Name=InstanceType,Value=$InstanceType --evaluation-periods 1 --alarm-actions $TopicARN --unit Percent 2>&1)


if [[ "$MEM_Alarm_Output" == *"InvalidParameter"* ]];then
  echo -ne "\n\e[31m Error: $MEM_Alarm_Output\e[00m\n"
  exit
else     
  echo -ne "\n\e[32m The $alarmname is created succesfully!!!\e[00m \n"
exit
fi
}

##Recall the function to add Additional Emails to the Topic
Add_Multiple_Emails(){
User_Input_Email
Add_Additional_Email
}

##Establishing Run Order
main() {
AwsCliCheck	
User_Input
Create_And_Verify_TopicName
Create_And_Verify_Subcription
User_Input_Email
Add_Additional_Email
}

main
