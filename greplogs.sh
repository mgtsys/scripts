#!/bin/bash


Define_Variables() {

int=^[0-9]+[/]+[0-9]+[/]+[0-9]
MonthString=("01Jan" "02Feb" "03Mar" "04Apr" "05May" "06Jun" "07Jul" "08Aug" "09Sep" "10Oct" "11Nov" "12Dec")

}

##Verify the Input Date is in correct format 
Verify_Date() {

echo -ne "\nEnter the Date in (dd/mm/yyyy) format: "
read startdate

if ! [[ $startdate =~ $int ]] && ! [[ ${#startdate} == 10 ]]
  then  
  echo -e "\nPlease enter the date in the correct format as: 01/01/2021"
exit
fi

}

##User Input Data to extract Logs
User_Input() {

echo -ne "\nEnter the Start time in (00:00:00) 24Hrs format: "
read starttime

echo -ne "\nEnter the End time in (00:00:00) 24Hrs format: "
read endtime

echo -ne "\nEnter the Path of Access logs: "
read logpath

}

##Covert Input Month from Integer to String
Convert_Input_Month() {

StartMonth=$(echo "$startdate" | cut -d "/" -f2)

for i in ${MonthString[@]}; do
  if [[ "$i"  =~ "$StartMonth" ]]; then
j=$(echo "$i" | sed 's/[0-9]*//')
FinalDate=$(echo $startdate | sed 's/\/'$StartMonth'/\/'$j'/')

fi
done

}

##Extract Unique IPs with AWK 
Extract_Unique_IPs() {

if [ -f "$logpath/access.log" ]; then 
IP=$(cat "$logpath/access.log" | awk '$4 >= "['$FinalDate':'$starttime'" && $4 < "['$FinalDate':'$endtime'"' | awk -F " " '{print $1}' | sort | uniq -c | sort -k1 -n | tail -10) 
else
  echo -e "\nPlease make sure the access.log exist at the $logpath path"
  exit

fi

if [ -z "$IP" ]; then
   echo -e "\nNo logs present for the entered timeframe, please recheck the input date/time"	
exit
   else
echo -e "\nList of the Top 10 Unique IPs for the selected time frame is as following:"	   
echo -e "\n$IP"

fi

}

##Extract the User Agent with AWK
Extract_UA() {

if [ -f "$logpath/access.log" ]; then 
UA=$(cat "$logpath/access.log" | awk '$4 >= "['$FinalDate':'$starttime'" && $4 < "['$FinalDate':'$endtime'"' | awk -F '"-"' '{print $2}' | sort | uniq -c | sort -k1 -n | tail -10) 
else
  echo -e "\nPlease make sure the access.log exist at the $logpath path"
  exit

fi

if [ -z "$UA" ]; then
   echo -e "\nNo logs present for the entered timeframe, please recheck the input date/time"	
exit
   else
echo -e "\nList of the Top 10 User-Agents for the selected time frame is as following:"	   
echo -e "\n$UA"

fi

}


##Extract the Bots with Grep
Extract_Bots() {

if [ -f "$logpath/access.log" ]; then 
Bots=$(cat "$logpath/access.log" | awk '$4 >= "['$FinalDate':'$starttime'" && $4 < "['$FinalDate':'$endtime'"' | grep -oh -E "\w*Bot\w*|\w*bot" |sort | uniq -c | sort -k1 -n | tail -10) 
else
  echo -e "\nPlease make sure the access.log exist at the $logpath path"
  exit

fi

if [ -z "$Bots" ]; then
   echo -e "\nNo logs present for the entered timeframe, please recheck the input date/time"	
exit
   else
echo -e "\nList of the Top 10 Bots for the selected time frame is as following:"	   
echo -e "\n$Bots"

fi

}


##Extract Top 10 URLs hit with AWK 
Extract_URLs() {

if [ -f "$logpath/access.log" ]; then 
URL=$(cat "$logpath/access.log" | awk '$4 >= "['$FinalDate':'$starttime'" && $4 < "['$FinalDate':'$endtime'"' | awk -F " " '{print $7}' | sort | uniq -c | sort -k1 -n | tail -10) 
else
  echo -e "\nPlease make sure the access.log exist at the $logpath path"
  exit

fi

if [ -z "$URL" ]; then
   echo -e "\nNo logs present for the entered timeframe, please recheck the input date/time"	
exit
   else
echo -e "\nList of the Top 10 URLs hit for the selected time frame is as following:"	   
echo -e "\n$URL"

fi

}


##Establish Run Order
main () {

Define_Variables
Verify_Date
User_Input
Convert_Input_Month
Extract_Unique_IPs
Extract_UA
Extract_Bots
Extract_URLs
}

main
