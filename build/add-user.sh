#!/bin/bash

Url=${1:-http://hrbc1-web.localvm:81}
input=${2:-add-user.txt}

[ -n "$Url" ] || { echo "Need URL!"; exit 2; }
[ -f "$input" ] || { echo "Input file $input not found or not readable"; exit 2; }

for line in $(cat $input); 
do 
	CId=$(echo $line | cut -d"," -f1);
	CompanyLoginId=$(echo $line | cut -d"," -f2);
	Mail=$(echo $line | cut -d"," -f3);
	Password=$(echo $line | cut -d"," -f4);
	Name=$(echo $line | cut -d"," -f5);
	: ${Name:=TestUser}
	DeptId=$(echo $line | cut -d"," -f6);
	: ${DeptId:=1001}
	TimeZone=$(echo $line | cut -d"," -f7);
	: ${TimeZone:=Asia/Tokyo}
	Administrator=$(echo $line | cut -d"," -f8);
	: ${Administrator:=true}
	Language=$(echo $line | cut -d"," -f9);
	: ${Language:=ja}
	StartDate=$(echo $line | cut -d"," -f10);
	: ${StartDate:=$(date +'%Y/%m/%d')}
	EndDate=$(echo $line | cut -d"," -f11 | tr -d '\r');

	if [[ -n "$EndDate" ]]
	then
		enddatejson=',"User.P_EndDate":"'$EndDate'"'
	else
		enddatejson=""
	fi;

	echo "Creating User $CompanyLoginId $Name:"
	UPid="$(curl -s -f -H "x-identity:CID=$CId;UID=1;SERVICE=Test" -H "Content-Type:application/json" -d '{"User.P_Name":"'$Name'","User.P_DeptId":'$DeptId',"User.P_Mail":"'$Mail'","User.P_Username":"'$Mail'","User.P_TimeZone":"'$TimeZone'","User.P_Language":"'$Language'","User.P_StartDate":"'$StartDate'"'$enddatejson',"User.P_Administrator":'true'}' "$Url/privateapi/v2/user" | jq -r .\"User.P_Id\")" || { echo "Failed Creating the new user"; exit 1; }
		
	token="$(curl -s -f -H "x-identity:CID=$CId;UID=1;SERVICE=Test" -H "Content-Type:application/json" -d '{"companyLoginId":"'$CompanyLoginId'","username":"'$Mail'"}' "$Url/privateapi/authentication/token" | jq -r .token)"
	[ -n "$token" ] || { echo "Failed(Token)"; exit 1; }

	curl -s -f -H "x-identity:CID=$CId;UID=1;SERVICE=Test" -H "Content-Type:application/json" -d '{"token":"'$token'","companyLoginId":"'$CompanyLoginId'","username":"'$Mail'","newPassword":"'$Password'"}' "$Url/privateapi/authentication/reset-password" || { echo "Failed(Password)"; exit 1; }
		
	if [[ "$Administrator" = "false" ]];
	then
		curl -s -f -H "x-identity:CID=$CId;UID=1;SERVICE=Test" -H "Content-Type:application/json" -X PUT -d '{"User.P_Id":"'$UPid'","User.P_Administrator":'$Administrator'}' "$Url/privateapi/v2/user"
	else
		echo "The value of Administrator is not <FALSE>."
	fi;
	echo "Ok"
done;
