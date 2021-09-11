#!/usr/bin/env bash

#This is a Unimus to Git API to export your backups to your Git Repo

#Imports from env


function echoGreen(){
	green='\033[0;32m' 
	echo -e "${green}$1${reset}"; 
}


function echoYellow(){ 
	yellow='\033[1;33m'
	echo -e "${yellow}$1${reset}"; 
}


function echoRed(){ 
	red='\033[0;31m'
	echo -e "${red}$1${reset}"; 
}


#This function will do a get request 
function unimus_get(){
	local get_request=$(curl -s -H "Accept: application/json" -H "Authorization: Bearer $unimus_api_key" "$unimus_server/api/v2/$1")
	echo "$get_request"
}


#Verify's Server is online
function unimus_status_check(){
	local get_status=$(unimus_get "health")
	local status=$(jq -r '.data.status' <<< $get_status)
	echo "$status"
}


#Decodes and Saves File
function save_file(){
	local address=${devices[$1]}
	local date="$2"
	if [[ $4 == "TEXT" ]]; then
		local type="txt"
	elif [[ $4 == "BINARY" ]]; then
		local type ="bin"
	fi

	if ! [ -d "backups" ]; then
		mkdir backups
		if [ $? -ne 0 ] ; then
			echoRed "Failed to create backups folder!"
			exit 2
		fi
	fi

	if ! [ -d "$backup_dir/$address - $1" ]; then
		mkdir "$backup_dir/$address - $1"
		if [ $? -ne 0 ] ; then
			echoRed "Failed to create device folder!"
			exit 2
		fi
	fi
	if ! [ -e $backup_dir/$address\ -\ $1/Backup\ $address\ $date\ $1.$type ]; then
		base64 -d <<< $3 > $backup_dir/$address\ -\ $1/Backup\ $address\ $date\ $1.$type
	fi
}


function get_allDevices(){
	echoGreen "Getting Device Information" >> $log
	for ((page=0; ; page+=1)); do

		local contents=$(unimus_get "devices?page=$page")
		
		for((data=0; ; data+=1)); do
			if ( jq -e '.data['$data'] | length == 0' <<< $contents) >/dev/null; then
				break
			fi
			if $(echo "$contents" | ${devices[(jq -e ' .data['$data']')]}) >/dev/null; then
				read -a value < <(echo $(jq -e '.data['$data'] | .id, .address' <<< $contents))
				devices[${value[0]}]=$(echo ${value[1]}  | tr -d '"')
			fi
		done

		if ( jq -e '.data | length == 0' <<< $contents ) >/dev/null; then
			break
		fi 
	done
}


function get_all_backups(){
	for key in "${!devices[@]}"; do
		for ((page=0; ; page+=1));do
			local contents=$(unimus_get "devices/$key/backups?page=$page")
			for ((data=0; ; data+=1)); do
				if  ( jq -e '.data['$data'] | length == 0' <<<  $contents) >/dev/null; then
					break
				fi

				local deviceId=$key
				local date="$(jq -e -r '.data['$data'].validSince' <<< $contents | { read tme ; date "+%F-%T-%Z" -d "@$tme" ; })"
				local backup=$(jq -e -r '.data['$data'].bytes' <<< $contents)
				local type=$(jq -e -r '.data['$data'].type' <<< $contents)
				save_file "$deviceId" "$date" "$backup" "$type"
			done
		if [ $(jq -e '.data | length == 0' <<< $contents) ] >/dev/null; then
				break
		fi 
		done
	done
}


#Will Pull down backups and save to Disk
function get_latest_backups(){

	#Query for latest backups. This will loop through getting every page

	for ((i=0; ; i+=1)); do
		local contents=$(unimus_get "devices/backups/latest?page=$i")

		for ((j=0; ; j+=1)); do

			#Breaks if looped through all devices
			if  ( jq -e '.data['$j'] | length == 0' <<<  $contents) >/dev/null; then
				break
			fi

			local deviceId=$(jq -e -r '.data['$j'].deviceId' <<< $contents)
			local date="$(jq -e -r '.data['$j'].backup.validSince' <<< $contents | { read tme ; date "+%F-%T-%Z" -d "@$tme" ; })"
			local backup=$(jq -e -r '.data['$j'].backup.bytes' <<< $contents)
			local type=$(jq -e -r '.data['$j'].backup.type' <<< $contents)

			save_file "$deviceId" "$date" "$backup" "$type"

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
			git remote add orgin ssh://$git_username@$git_server_address/$git_repo_name 
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
		git commit -m $"date" 
		git push 
	fi
	cd $script_dir
}

function check_vars(){
	if [[ -z "$1" ]]; then
		echoRed "$2 is not set in unimus-backup-exporter.env"
		exit 2
	fi
}

function importVariables(){
	set -a # automatically export all variables
	source UnimusGit.env
	set +a

	check_vars "$unimus_server" "unimus_server"
	check_vars "$unimus_api_key" "unimus_api_key"
	check_vars "$backup_type" "backup_type"
	check_vars "$export_type" "export_type"

	if [[ "$export_type" == "git" ]]; then
		check_vars "$git_username" "git_username"
		check_vars "$git_password" "git_password"
		check_vars "$git_email" "git_email"
		check_vars "$git_server_protocal" "git_server_protocal"
		check_vars "$git_server_address" "git_server_address"
		check_vars "$git_port" "git_port"
		check_vars "$git_repo_name" "git_repo_name"
		check_vars "$git_branch" "git_branch"
	fi
}

function main(){
	importVariables

	#Set Directorys for script
	script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
	backup_dir=$script_dir/backups



	#HashTable for all devices
	declare -A devices
	log=$script_dir/unimus-backup-exporter.log

	#Creating a log file
	printf "Log File - " >> $log
	date >> $log
	local status=$(unimus_status_check)
	if [[ $status == "OK" ]]; then
		#Getting All Device Information
		echoGreen "Getting Device Data"
		get_allDevices

		#Chooses what type of backup we will do.
		case $backup_type in
			latest)
			get_latest_backups
			;;
			all)
			get_all_backups
			;;
			*)
			echoRed "Invalid Setting for backup_type" >> $log
			;;
		esac

		#If no server protocal is selected we will not push to git.
		#Otherwise We push to Git
		case $export_type in 
			git)
			pushToGit
			echoGreen "Exporting to Git" >> $log
			;;
			fs)
			echoGreen "Exporting to FS"	>> $log
			;;
			*)
			echoRed "No export type defined."
			exit 2
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