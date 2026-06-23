#!/usr/bin/env bash
# shellcheck disable=SC2154
# Config vars (unimus_*, backup_type, export_type, git_*, insecure) are defined
# in unimus-backup-exporter.env, sourced at runtime by importVariables(); the
# linter cannot see where they are assigned, hence the disable above.

# This is a Unimus to Git API to export your backups to your Git Repo


# $1 is echo message
function echoGreen(){
	printf '%s %s\n' "$(date +'%F %H:%M:%S')" "$1" >> "$log"
	local green='\033[0;32m'
	local reset='\033[0m'
	echo -e "${green}$1${reset}"
}


# $1 is echo message
function echoYellow(){
	printf 'WARNING: %s %s\n' "$(date +'%F %H:%M:%S')" "$1" >> "$log"
	local yellow='\033[1;33m'
	local reset='\033[0m'
	echo -e "WARNING: ${yellow}$1${reset}"
}


# $1 is echo message
function echoRed(){
	printf 'ERROR: %s %s\n' "$(date +'%F %H:%M:%S')" "$1" >> "$log"
	local red='\033[0;31m'
	local reset='\033[0m'
	echo -e "ERROR: ${red}$1${reset}"
}


# $1 is $? from the command being checked
# #2 is the error message
function errorCheck(){
	if [ "$1" -ne 0 ]; then
		echoRed "$2"
		exit "$1"
	fi
}


# Checks github for latest release
function checkLatestVersion(){
	if ! lastest_version=$(curl -sL 'https://api.github.com/repos/netcore-jsa/unimus-backup-exporter/releases/latest' | jq -r '.tag_name'); then
		echoYellow "Failed to check for updated script"
		return 2
	fi
	lastest_version=${lastest_version#'v'}
	local i
	local -a ver1 ver2
	IFS='.' read -ra ver1 <<< "$lastest_version"
	IFS='.' read -ra ver2 <<< "$SCRIPT_VERSION"
	if [ "${ver1[0]}" == "${ver2[0]}" ]; then
		return 0
	fi
	# fill empty fields in ver1 with zeros
	for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
		ver1[i]=0
	done
	for ((i=0; i<${#ver1[@]}; i++)); do
		if [ -z "${ver2[i]}" ]; then
			# fill empty fields in ver2 with zeros
			ver2[i]=0
		fi
		if ((10#${ver1[i]} > 10#${ver2[i]})); then
			echoYellow 'You are using an older version of this script. It is recommended to upgrade.'
			return 1
		fi
	done
	return 0
}


# This function will do a get request
# $1 is the api request
function unimusGet(){
	local get_request
	# $insecure is intentionally unquoted: it is empty, or "-k" for self-signed certs.
	# shellcheck disable=SC2086
	get_request=$(curl $insecure -s -H 'Accept: application/json' -H "Authorization: Bearer $unimus_api_key" "$unimus_server_address/api/v2/$1")
	errorCheck "$?" 'Unable to get data from unimus server'
	echo "$get_request"
}


# Verify's Server is online
function unimusStatusCheck(){
	local get_status
	get_status=$(unimusGet 'health')
	local status
	status=$(jq -r '.data.status' <<< "$get_status")
	errorCheck "$?" 'Unable to peform unimus Status Check'
	echo "$status"
}


# $1 is the device id
# $2 is the date of the backup
# $3 is the base64 encoded backup
# $4 is the backup type
# Decodes and Saves Backup
function saveBackup(){
	local address="${devices[$1]}"
	# Separator between name parts; defaults to a space for backward compatibility.
	local sep="${separator:- }"
	local type
	if [ "$4" == 'TEXT' ]; then
		type='txt'
	elif [ "$4" == 'BINARY' ]; then
		type='bin'
	fi
	local dir="$backup_dir/${address}${sep}-${sep}${1}"
	local file="$dir/Backup${sep}${address}${sep}${2}${sep}${1}.${type}"
	if ! [ -d "$dir" ]; then
		mkdir "$dir"
		errorCheck "$?" 'Failed to create device folder'
	fi
	if ! [ -e "$file" ]; then
		base64 -d <<< "$3" > "$file"
	fi
}


function getAllDevices(){
	echoGreen 'Getting Device Information'
	# Device field used to name folders; defaults to the address (the IP).
	local field="${device_name_field:-address}"
	for ((page=0; ; page+=1)); do
		local contents rows id address name
		contents=$(unimusGet "devices?page=$page")
		errorCheck "$?" 'Unable to get device data from unimus'
		# Parse the whole page once into id/address/name TSV rows (one jq call
		# per page rather than several per device).
		rows=$(jq -r --arg f "$field" '.data[] | [.id, .address, (.[$f] // "")] | @tsv' <<< "$contents")
		if [ -z "$rows" ]; then
			break
		fi
		while IFS=$'\t' read -r id address name; do
			# Fall back to the address if the chosen field is empty or missing.
			if [ -z "$name" ]; then
				name="$address"
			fi
			devices["$id"]="$name"
		done <<< "$rows"
	done
}


function getAllBackups(){
	local backupCount=0
	for key in "${!devices[@]}"; do
		for ((page=0; ; page+=1)); do
			local contents rows validSince type backup date
			contents=$(unimusGet "devices/$key/backups?page=$page")
			errorCheck "$?" 'Unable to get all backups from unimus'
			# One jq pass per page emits validSince/type/bytes TSV rows.
			rows=$(jq -r '.data[] | [.validSince, .type, .bytes] | @tsv' <<< "$contents")
			if [ -z "$rows" ]; then
				break
			fi
			while IFS=$'\t' read -r validSince type backup; do
				date=$(date "+%F-%T-%Z" -d "@$validSince")
				saveBackup "$key" "$date" "$backup" "$type"
				backupCount=$((backupCount + 1))
			done <<< "$rows"
		done
	done
	echoGreen "$backupCount backups exported"
}


# Will Pull down backups and save to Disk
function getLatestBackups(){
	local backupCount=0
	# Query for latest backups. This will loop through getting every page
	for ((page=0; ; page+=1)); do
		local contents rows deviceId validSince type backup date
		contents=$(unimusGet "devices/backups/latest?page=$page")
		errorCheck "$?" 'Unable to get latest backups from unimus'
		# One jq pass per page emits deviceId/validSince/type/bytes TSV rows.
		rows=$(jq -r '.data[] | [.deviceId, .backup.validSince, .backup.type, .backup.bytes] | @tsv' <<< "$contents")
		if [ -z "$rows" ]; then
			break
		fi
		while IFS=$'\t' read -r deviceId validSince type backup; do
			date=$(date "+%F-%T-%Z" -d "@$validSince")
			saveBackup "$deviceId" "$date" "$backup" "$type"
			backupCount=$((backupCount + 1))
		done <<< "$rows"
	done
	echoGreen "$backupCount backups exported"
}


function pushToGit(){
	if ! cd "$backup_dir"; then
		echoRed 'Failed to enter backup directory'
		exit 1
	fi
	if ! [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" ]; then
		git init
		git config user.email "$git_email"
		git config user.name "$git_username"
		git add .
		git commit -m 'Initial Commit'
		case "$git_server_protocol" in
			ssh)
			ssh-keyscan -H "$git_server_address" >> ~/.ssh/known_hosts
			if [ -z "$git_password" ]; then
				git remote add origin "ssh://$git_username@$git_server_address/$git_repo_name"
				errorCheck "$?" 'Failed to add git repo'
			else
				git remote add origin "ssh://$git_username:$git_password@$git_server_address/$git_repo_name"
				errorCheck "$?" 'Failed to add git repo'
			fi
			;;
			http)
			git remote add origin "http://$git_username:$git_password@$git_server_address:$git_port/$git_repo_name"
			errorCheck "$?" 'Failed to add git repo'
			;;
			https)
			git remote add origin "https://$git_username:$git_password@$git_server_address:$git_port/$git_repo_name"
			errorCheck "$?" 'Failed to add git repo'
			;;
			*)
			echoRed 'Invalid setting for git_server_protocol'
			exit 2
			;;
		esac
		git push -u origin "$git_branch" >> "$log"
		errorCheck "$?" 'Failed to add branch'
		git push >> "$log"
		errorCheck "$?" 'Failed to push to git'
	else
		git add --all
		git commit -m "Unimus Git Extractor $(date +'%b-%d-%y %H:%M')"
		git push
		errorCheck "$?" 'Failed to push to git'
	fi
	if ! cd "$script_dir"; then
		exit 1
	fi
}


# We can't pass the variable name in any other way
# $1 is the variable
# $2 is the name
function checkVars(){
	if [ -z "$1" ]; then
		echoRed "$2 is not set in unimus-backup-exporter.env"
		exit 2
	fi
}


function importVariables(){
	set -a # Automatically export all variables
	# shellcheck source=/dev/null
	source unimus-backup-exporter.env
	set +a
	checkVars "$unimus_server_address" 'unimus_server_address'
	checkVars "$unimus_api_key" 'unimus_api_key'
	checkVars "$backup_type" 'backup_type'
	checkVars "$export_type" 'export_type'
	if [ "$export_type" == 'git' ]; then
		checkVars "$git_username" 'git_username'
		# Only Checking for password for http. SSH may or may not require a password
		if [[ "$git_server_protocol" == 'http' || "$git_server_protocol" == 'https' ]]; then
			if [ -z "$git_password" ]; then
				echoRed 'Please Provide a git password'
				exit 2
			fi
		fi
		checkVars "$git_email" 'git_email'
		checkVars "$git_server_protocol" 'git_server_protocol'
		checkVars "$git_server_address" 'git_server_address'
		checkVars "$git_port" 'git_port'
		checkVars "$git_repo_name" 'git_repo_name'
		checkVars "$git_branch" 'git_branch'
	fi
}


function main(){
	SCRIPT_VERSION='1.1.0'

	# Set script directory and working dir for script
	script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
	if ! cd "$script_dir"; then
		exit 1
	fi
	backup_dir="$script_dir/backups"

	# HashTable for all devices
	declare -A devices

	# Create Backup Folder
	if ! [ -d 'backups' ]; then
		mkdir backups
		errorCheck "$?" 'Failed to create backup folder'
	fi

	# Creating a log file
	log="$script_dir/unimus-backup-exporter.log"
	printf 'Log File - ' >> "$log"
	date +"%F %H:%M:%S" >> "$log"

	checkLatestVersion

	# Importing variables
	importVariables

	status=$(unimusStatusCheck)
	errorCheck "$?" 'Status check failed'

	if [ "$status" == 'OK' ]; then
		# Getting All Device Information
		echoGreen 'Getting device data'
		getAllDevices

		# Chooses what type of backup we will do
		case "$backup_type" in
			latest)
			echoGreen 'Exporting latest backups'
			getLatestBackups
			echoGreen 'Export successful'
			;;
			all)
			echoGreen 'Exporting all backups'
			getAllBackups
			echoGreen 'Export successful'
			;;
		esac

		# Exporting to git
		if [ "$export_type" == 'git' ]; then
			echoGreen 'Pushing to git'
			pushToGit
			echoGreen 'Push successful'
		fi
	else
		if [ -z "$status" ]; then
			echoRed 'Unable to connect to unimus server'
			exit 2
		else
			echoRed "Unimus server status: $status"
		fi
	fi
	echoGreen 'Script finished'
}


main
