# Unimus Backup Exporter

The Unimus backup exporter exports backups from your [Unimus](https://unimus.net) server, stores them locally, and pushes them to a git repo if desired. It ships as two interchangeable, fully-featured implementations - a Bash script and a PowerShell script - that read the same config and produce identical output. Use whichever fits your environment.

## _Requirements_

The Bash version (`unimus-backup-exporter.sh`) requires `bash`, `curl`, `jq`, and `base64`. The PowerShell version (`unimus-backup-exporter.ps1`) requires `pwsh` (PowerShell 7+).

Pushing to git (`export_type=git`) additionally needs `git` for either version, plus `ssh-keyscan` when using the `ssh` protocol.

The PowerShell version targets Linux/macOS - the backup filenames contain `:` (from the timestamp), which is not a legal filename character on Windows.

## _How to use the Exporter_

To use the exporter, you must configure the script's env file with your settings. The script can extract all backups, or just the latest backups, depending on configuration.

If you are using this script to push backups to git, it will create a local git directory based on the settings in your env file, and then push backups to that repo.

* Configure the env with the appropriate variables for your install as described in the Configuration File section.

* To execute the script, run one of the following in the script directory:

``` bash
./unimus-backup-exporter.sh      # Bash
pwsh ./unimus-backup-exporter.ps1   # PowerShell
```

After the script runs, you will find your backups nested in a "backups" folder. Each device's backups are in their own folder, labeled by the device address and the Unimus device ID.

Both versions are interchangeable: they read the same `unimus-backup-exporter.env`, write the same `backups/` tree, and push to git the same way. A shared test suite verifies their output is byte-identical, so you can switch between them or run them against the same backup repo.

## _Configuration File_

The most basic requirements for the script to operate are:

``` text
|        Setting        |         Value             |
|  -------------------  |  -----------------------  |
| unimus_server_address | "http://192.168.0.1:8085" |
| unimus_api_key        | "your unimus api key"     |
| backup_type           | "all" or "latest"         |
| export_type           | "git" or "fs"             |
```

backup_type
 - "all" will download all backups when the script is run
 - "latest" will download only the latest backup each time the script is run

export_type
 - "git" will push the backups to your git repo
 - "fs" will keep the backups on the local fs

If your Unimus server uses a self-signed certificate, you can skip TLS certificate verification by uncommenting `insecure="-k"` in the env file. Leave it commented out otherwise.

In addition to these basic requirements, using git requires some of these additional settings:

``` text
|       Setting       |          Value           |
|  -----------------  |  ----------------------  |
| git_username        | "foo"                    |
| git_password        | "bar"                    |
| git_email           | foo@bar.com              |
| git_server_protocol | "http", "https" or "ssh" |
| git_server_address  | "192.168.1.1"            |
| git_port            | "80"                     |
| git_repo_name       | "Foo/Backups.git"        |
| git_branch          | "master"                 |
```
Depending on your git server you may not require a password (the password is only required for the `http`/`https` protocols).

## _Automating the exporter_

To run your script periodically, the most common solution is scheduling a cron job. Adding the following line to `crontab -e` will set up the script to run every night at 3AM:

```
0 3 * * * /path-to-script/unimus-backup-exporter.sh
```

## _Tests_

A shared test suite under `tests/` runs both the Bash and PowerShell versions against a mock Unimus API and asserts byte-identical output (plus identical git behavior). Run everything with:

``` bash
tests/run.sh
```

See [tests/README.md](tests/README.md) for details on the layers and how to run them individually.
