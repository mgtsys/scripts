#!/bin/bash

##Defining Variables
Define_Variables() {

int=^[0-9]
intdate=^[0-9]+[/]+[0-9]+[/]+[0-9]
inttime=^[0-9]+[:]+[0-9]+[:]+[0-9]
MonthString=("01Jan" "02Feb" "03Mar" "04Apr" "05May" "06Jun" "07Jul" "08Aug" "09Sep" "10Oct" "11Nov" "12Dec")

}

##Verify the Users Input Data is in correct format
Verify_User_Input() {

echo -ne "\n1) Enter the Date in (dd/mm/yyyy) format: "
read startdate

if ! [[ $startdate =~ $intdate ]] || ! [[ ${#startdate} == 10 ]]; then
 echo -e "\nPlease enter the date in the correct format as: 01/01/2021"
exit
fi

echo -ne "2) Enter the Start time in (00:00:00) 24Hrs format: "
read starttime

if ! [[ $starttime =~ $inttime ]] || ! [[ ${#starttime} == 8 ]]; then
  echo "Please enter the Time in the correct format as: 00:00:00"
  exit
fi

echo -ne "3) Enter the End time in (00:00:00) 24Hrs format: "
read endtime

if ! [[ $endtime =~ $inttime ]] || ! [[ ${#starttime} == 8 ]]; then
  echo "Please enter the Time in the correct format as: 00:00:00"
  exit
fi

echo -ne "4) Enter the Absolute Path of Access logs: "
read logpath

if ! [ -f "$logpath/access.log" ]; then
 echo -e "\nPlease make sure the "access.log" exist at the "$logpath" path"
 exit
fi

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


##Validate the Extracted Ips to the Abuse IPs Database
Abuse_IPs() {

##Strip HIT cout and IP address
for k in ${IP[@]}; do
   if [[ "${#k}" -le "2" ]];then
IPHitCount=$k
else
AbuseIP=$k

for i in ${AbuseIP[@]}; do

##API Call To Fetch Json
jsonout=$(curl -s -G https://api.abuseipdb.com/api/v2/check --data-urlencode "ipAddress=$i" -d maxAgeInDays=90 -d verbose  -H "Key: d8dc9983dc9b8364f5208f6b706dcbed4dda697e9a6cf922636a49c6b865054aaf70c75ee5147939" -H "Accept: application/json")

echo -ne "\n*IP Address: $i"

##Abuse Confidence Score
AbuseConfidenceScore=$(echo $jsonout | awk -F [:] '{print $7}' | cut -d "," -f1)
echo -ne "\n The Abuse Confidence Score is $AbuseConfidenceScore% \n"

##Origin Country
OriginCountry=$(echo $jsonout | awk -F [:] '{print $13}' | cut -d "," -f1)
echo -ne " The IP origin country is $OriginCountry \n"

##Domain Name
DomainName=$(echo $jsonout | awk -F [:] '{print $11}' | cut -d "," -f1)
echo -ne " The IP domain name is $DomainName \n"

done
   fi
done
}

Options_Select() {

echo -ne "\n Please choose appropirate options for the desired output: \n"

echo -ne "\n 1) Enter 1 to Extract Top 10 Unique IPs"
echo -ne "\n 2) Enter 2 to Extract Top 10 User Agents"
echo -ne "\n 3) Enter 3 to Extract Top 10 Bots"
echo -ne "\n 4) Enter 4 to Extract Top 10 Urls"
echo -ne "\n 5) Enter 5 to Extract All the Above"
echo -ne "\n 6) Enter 6 to Extract Top 10 Unique IPs and verify them with Abuse IPs database\n"

echo -ne "\n Enter Your Option: "
read option

if [ "$option" = 1 ]; then
    Extract_Unique_IPs
    exit
elif
    [ "$option" = 2 ];then
    Extract_UA
    exit
elif
    [ "$option" = 3 ];then
    Extract_Bots
    exit
elif
    [ "$option" = 4 ];then
    Extract_URLs
    exit
elif
    [ "$option" = 5 ];then
    Extract_Unique_IPs
    Extract_UA
    Extract_Bots
    Extract_URLs
    exit
elif
   [ "$option" = 6 ];then
   Extract_Unique_IPs
   Abuse_IPs
   exit
elif
  ! [[ "$option" =~ "$int" ]] ; then
   echo -ne "\n Please Enter number from ( 1 - 5 ) to display correct output \n"
exit
fi
}



##Establish Run Order
main () {

Define_Variables
Verify_User_Input
Convert_Input_Month
Options_Select
#Extract_Unique_IPs
#Extract_UA
#Extract_Bots
#Extract_URLs
#Abuse_Ips
}

main
