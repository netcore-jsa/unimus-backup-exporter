# Unimus Backup Exporter 

The Unimus backup exporter is a bash script that exports backups from your Unimus server, store backups locally, and push them to a git repo if desired.

## _Requirements_

The only requirements for this script are bash, jq, and base64. 

## _How to use the Exporter_ 

To use the exporter, you must configure the scripts env file with your credentials. The script call extract all backups, or just the latest backups depending on configuration. 

If you are using this script to push backups to git, it will create a git repo based on the settings in your env file, and then push backups to that repo. 

## _Configuration File_

The most basic requirements for the script to operate are. 

| Setting | Value |
| ------ | ------ |
| unimus_server_address | "http://192.168.0.1:8085" |
| unimus_api_key | "your unimus api key" |
| backup_type | "all" or "latest" |
| export_type | "git" or "fs" |

backup_type
 - "all" will download all backups when the script is run
 - "latest" will download only the when every time the script is run. 
 
export_type
 - "git" will push the backups to your git repo
 - "fs" will keep the backups on the local fs.
 
In addition to these basic requirements, using git requires some of these additional requirements. 

| Setting | Value |
| ------ | ------ |
| git_username | "foo" |
| git_password | "bar" |
| git_email | foo@bar.com |
| git_server_protocal | "http", "https" or "ssh" |
| git_server_address | "192.168.1.1" |
| git_port | "80" |
| git_repo_name | "Foo/Backups.git" |
| git_branch | "master" |
 
 Depending on your git server. For example, if you are using an ssh key, you may not require a password. 