#!/usr/bin/env bash

#This is a Unimus to Git API to export your backups to your Git Repo


# $1 is echo message
function echoGreen(){
	printf "$1\n" >> $log
	local green='\033[0;32m'
	local reset='\033[0m'
	echo -e "${green}$1${reset}"; 
}


# $1 is echo message
function echoYellow(){ 
	printf "$1\n" >> $log
	local yellow='\033[1;33m'
	local reset='\033[0m'
	echo -e "${yellow}$1${reset}"; 
}


# $1 is echo message
function echoRed(){ 
	printf "$1\n" >> $log
	local red='\033[0;31m'
	local reset='\033[0m'
	echo -e "${red}$1${reset}"; 
}


#This function will do a get request 
# $1 is the api request
function unimusGet(){
	local get_request=$(curl -s -H "Accept: application/json" -H "Authorization: Bearer $unimus_api_key" "$unimus_server_address/api/v2/$1")
	echo "$get_request"
}


#Verify's Server is online
function unimusStatusCheck(){
	local get_status=$(unimusGet "health")
	local status=$(jq -r '.data.status' <<< $get_status)
	echo "$status"
}


# $1 is the device id. 
# $2 is the date of the backup
# $3 is the base64 encoded backup
# $4 is the backup type. 
#Decodes and Saves Backup
function saveBackup(){
	local address=${devices[$1]}
	if [[ $4 == "TEXT" ]]; then
		local type="txt"
	elif [[ $4 == "BINARY" ]]; then
		local type ="bin"
	fi
	if ! [ -d "$backup_dir/$address - $1" ]; then
		mkdir "$backup_dir/$address - $1"
		if [ $? -ne 0 ] ; then
			echoRed "Failed to create device folder!"
			exit 2
		fi
	fi
	if ! [ -e "$backup_dir/$address - $1/Backup $address $2 $1.$type" ]; then
		base64 -d <<< $3 > "$backup_dir/$address - $1/Backup $address $2 $1.$type"
	fi
}


function getAllDevices(){
	echoGreen "Getting Device Information"
	for ((page=0; ; page+=1)); do
		local contents=$(unimusGet "devices?page=$page")
		for((data=0; ; data+=1)); do
			if ( jq -e ".data[$data] | length == 0" <<< $contents) >/dev/null; then
				break
			fi
			if $(echo "$contents" | ${devices[(jq -e " .data[$data]")]}) >/dev/null; then
				read -a value < <(echo $(jq -e ".data[$data] | .id, .address" <<< $contents))
				devices[${value[0]}]=$(echo ${value[1]}  | tr -d '"')
			fi
		done
		if ( jq -e '.data | length == 0' <<< $contents ) >/dev/null; then
			break
		fi 
	done
}


function getAllBackups(){
	for key in "${!devices[@]}"; do
		for ((page=0; ; page+=1));do
			local contents=$(unimusGet "devices/$key/backups?page=$page")
			for ((data=0; ; data+=1)); do
				if  ( jq -e ".data[$data] | length == 0" <<<  $contents) >/dev/null; then
					break
				fi
				local deviceId=$key
				local date="$(jq -e -r ".data[$data].validSince" <<< $contents | { read tme ; date "+%F-%T-%Z" -d "@$tme" ; })"
				local backup=$(jq -e -r ".data[$data].bytes" <<< $contents)
				local type=$(jq -e -r ".data[$data].type" <<< $contents)
				saveBackup "$deviceId" "$date" "$backup" "$type"
			done
		if [ $(jq -e '.data | length == 0' <<< $contents) ] >/dev/null; then
				break
		fi 
		done
	done
}


#Will Pull down backups and save to Disk
function getLatestBackups(){
	#Query for latest backups. This will loop through getting every page
	for ((page=0; ; pagae+=1)); do
		local contents=$(unimusGet "devices/backups/latest?page=$page")
		for ((data=0; ; data+=1)); do
			#Breaks if looped through all devices
			if  ( jq -e ".data[$data] | length == 0" <<<  $contents) >/dev/null; then
				break
			fi
			local deviceId=$(jq -e -r ".data[$data].deviceId" <<< $contents)
			local date="$(jq -e -r ".data[$data].backup.validSince" <<< $contents | { read tme ; date "+%F-%T-%Z" -d "@$tme" ; })"
			local backup=$(jq -e -r ".data[$data].backup.bytes" <<< $contents)
			local type=$(jq -e -r ".data[$data].backup.type" <<< $contents)
			saveBackup "$deviceId" "$date" "$backup" "$type"
		done

		#breaks if empty page.
		if [ $(jq -e '.data | length == 0' <<< $contents) ] >/dev/null; then
			break
		fi 
	done
}


function pushToGit(){
	cd $backup_dir
	if ! [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" ]; then
		git init 
		git add . 
		git commit -m "Initial Commit"
		case $git_server_protocal in 
			ssh)
			ssh-keyscan -H git_server_address >> ~/.ssh/known_hosts
			if [[ -z "$git_password" ]]; then
				git remote add orgin ssh://$git_username@$git_server_address/$git_repo_name
			else
				git remote add orgin ssh://$git_username:$git_password@$git_server_address/$git_repo_name
			fi
			;;
			http)
			git remote add orgin http://$git_username:$git_password@$git_server_address:$git_port/$git_repo_name 
			;;
			https)
			git remote add orgin https://$git_username:$git_password@$git_server_address:$git_port/$git_repo_name 
			;;
			*)
			echoGreen "Invalid setting for git_server_protocal" 
			;;
		esac
		git push -u orgin $branch
		git push 
	else
		git add --all 
		git commit -m "Unimus Git Extractor $(date +'%b-%d-%y %H:%M')"
		git push 
	fi
	cd $script_dir
}


#We can't pass the variable name in any way. 
# $1 is the variable
# $2 is the name

function checkVars(){
	if [[ -z "$1" ]]; then
		echoRed "$2 is not set in unimus-backup-exporter.env"
		exit 2
	fi
}


function importVariables(){
	set -a # automatically export all variables
	source unimus-backup-exporter.env
	set +a
	checkVars "$unimus_server_address" "unimus_server_address"
	checkVars "$unimus_api_key" "unimus_api_key"
	checkVars "$backup_type" "backup_type"
	checkVars "$export_type" "export_type"
	if [[ "$export_type" == "git" ]]; then
		checkVars "$git_username" "git_username"
		#Only Checking for password for http. SSH may or may not require a password.
		if [[ -z "$git_server_protocal" == "ssh" ]]; then
			if [[ -z "$git_password" ]]; then
				echoRed "Please Provide a git password"
				exit 2
			fi
		fi
		checkVars "$git_email" "git_email"
		checkVars "$git_server_protocal" "git_server_protocal"
		checkVars "$git_server_address" "git_server_address"
		checkVars "$git_port" "git_port"
		checkVars "$git_repo_name" "git_repo_name"
		checkVars "$git_branch" "git_branch"
	fi
}


function main(){
	#Set Directorys for script
	script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
	backup_dir=$script_dir/backups
	#HashTable for all devices
	declare -A devices
	#Create Backup Folder
	if ! [ -d "backups" ]; then
		mkdir backups
		if [ $? -ne 0 ] ; then
			echoRed "Failed to create backups folder!"
			exit 2
		fi
	fi
	#Creating a log file
	log=unimus-backup-exporter.log
	printf "Log File - " >> $log
	date +"%b-%d-%y %H:%M" >> $log
	#Importing variables
	importVariables
	if [[ $(unimusStatusCheck) == "OK" ]]; then
		#Getting All Device Information
		echoGreen "Getting Device Data"
		getAllDevices

		#Chooses what type of backup we will do.
		case $backup_type in
			latest)
			getLatestBackups
			;;
			all)
			getAllBackups
			;;
		esac
		#If no server protocal is selected we will not push to git.
		#Otherwise We push to Git
		case $export_type in 
			git)
			pushToGit
			echoGreen "Exporting to Git"
			;;
			fs)
			echoGreen "Exporting to FS"
			;;
		esac
	else
		if [[ -z $status ]]; then
			echoRed "Unable to Connect to server"
		else
			echoRed "Server Status: $status "
		fi
	fi
}


main