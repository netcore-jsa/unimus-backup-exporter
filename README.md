# Unimus Backup Extractor

This repository contains the Unimus Backup Extractor.  
This extractor is used to create local copies of unimus device backups. 

### TL;DR
Requirements: `bash`, `jq`, `base64`.
```text
./unimus-backup-exporter.sh
``` 

### How does the exporter work?

The exporter is configured through a .env file. A sample .env file is provide. 

The Following are valid options for the .env file. 

    unimus_server=http://[address]:[Port]
    unimus_api_key="api_key"
    backup_type="[latest] or [historical]"

Valid options for git settings are as followed. If you do not wish to push to git, you can remove these, or put "none" in the git_server_protocal

    git_server_protocal="[http], [https], [ssh], or [none]"
    git_username="[username]"
    git_email="[email]"
    git_server_address="[address]"
    git_port="[port]"
    git_repo_name="[repo]"
    git_branch="[branch]"
    git_password="[password"

### Contributing
We welcome any Pull Requests or ideas for improvement / feedback.

