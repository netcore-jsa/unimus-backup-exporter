<#
.SYNOPSIS
  Fully-featured PowerShell alternative to unimus-backup-exporter.sh: pulls
  device backups from a Unimus server via its REST API, decodes them to disk,
  and optionally commits and pushes them to a Git repo.

  Reads the same unimus-backup-exporter.env and drives git the same way as the
  Bash version, with the same backups/<address> - <id>/ layout. The timestamp in
  each filename is UTC and ':'-free so the names are valid on Windows; this makes
  them differ from the Bash version's (which uses local time with ':'). git and
  ssh-keyscan are shelled out to; the timestamp is computed in .NET.

  Targets PowerShell 7+ on Windows, Linux, and macOS.
#>

# --- output helpers -------------------------------------------------------

function Write-Stamp([string]$prefix, [string]$message) {
	$ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
	[IO.File]::AppendAllText($log, "$prefix$ts $message`n")
}

function Write-EchoGreen([string]$message) {
	Write-Stamp '' $message
	Write-Host $message -ForegroundColor Green
}

function Write-EchoYellow([string]$message) {
	Write-Stamp 'WARNING: ' $message
	Write-Host "WARNING: $message" -ForegroundColor Yellow
}

function Write-EchoRed([string]$message) {
	Write-Stamp 'ERROR: ' $message
	Write-Host "ERROR: $message" -ForegroundColor Red
}

# Abort with $code and the given message when $code is non-zero.
function Invoke-ErrorCheck([int]$code, [string]$message) {
	if ($code -ne 0) {
		Write-EchoRed $message
		exit $code
	}
}

# --- version check --------------------------------------------------------

function Test-LatestVersion {
	try {
		$tag = (Invoke-RestMethod -Uri 'https://api.github.com/repos/netcore-jsa/unimus-backup-exporter/releases/latest').tag_name
	} catch {
		Write-EchoYellow 'Failed to check for updated script'
		return
	}
	if (-not $tag) { return }
	$tag = $tag -replace '^v', ''
	try {
		if ([version]$tag -gt [version]$SCRIPT_VERSION) {
			Write-EchoYellow 'You are using an older version of this script. It is recommended to upgrade.'
		}
	} catch {
		# Non-numeric tag; nothing to compare.
	}
}

# --- Unimus API -----------------------------------------------------------

# GET api/v2/<path>, returning the parsed JSON.
function Invoke-UnimusGet([string]$path) {
	$params = @{
		Uri                = "$unimus_server_address/api/v2/$path"
		Headers            = @{ Accept = 'application/json'; Authorization = "Bearer $unimus_api_key" }
		Method             = 'Get'
		SkipHttpErrorCheck = $true   # mirror curl: return the body even on 4xx/5xx
	}
	if ($insecure) { $params['SkipCertificateCheck'] = $true }
	try {
		return Invoke-RestMethod @params
	} catch {
		Write-EchoRed 'Unable to get data from unimus server'
		exit 1
	}
}

function Get-UnimusStatus {
	return (Invoke-UnimusGet 'health').data.status
}

# --- backup writing -------------------------------------------------------

# UTC timestamp with no ':' so the filename is valid on Windows.
function Format-BackupDate($epoch) {
	return [DateTimeOffset]::FromUnixTimeSeconds([long]$epoch).UtcDateTime.ToString('yyyy-MM-dd-HH-mm-ss') + '-UTC'
}

function Save-Backup($id, $date, $b64, $type) {
	$address = $devices[[string]$id]
	# Separator between name parts; defaults to a space for backward compatibility.
	$sep = if ([string]::IsNullOrEmpty($separator)) { ' ' } else { $separator }
	$ext = ''
	if ($type -eq 'TEXT') { $ext = 'txt' }
	elseif ($type -eq 'BINARY') { $ext = 'bin' }

	$dir = "$backup_dir/${address}${sep}-${sep}${id}"
	if (-not [IO.Directory]::Exists($dir)) {
		[IO.Directory]::CreateDirectory($dir) | Out-Null
	}
	$file = "$dir/Backup${sep}${address}${sep}${date}${sep}${id}.${ext}"
	if (-not [IO.File]::Exists($file)) {
		[IO.File]::WriteAllBytes($file, [Convert]::FromBase64String($b64))
	}
}

function Get-AllDevices {
	Write-EchoGreen 'Getting Device Information'
	# Device field used to name folders; defaults to the address (the IP).
	$field = if ([string]::IsNullOrEmpty($device_name_field)) { 'address' } else { $device_name_field }
	# Page size; bounds the JSON each request returns (matters on large installs).
	$size = if ([string]::IsNullOrEmpty($page_size)) { 50 } else { $page_size }
	$page = 0
	while ($true) {
		$contents = Invoke-UnimusGet "devices?size=$size&page=$page"
		$items = @($contents.data)
		foreach ($d in $items) {
			$name = $d.$field
			# Fall back to the address if the chosen field is empty or missing.
			if ([string]::IsNullOrEmpty($name)) { $name = $d.address }
			$devices[[string]$d.id] = [string]$name
		}
		if ($items.Count -eq 0) { break }
		$page++
	}
}

function Get-AllBackups {
	$backupCount = 0
	$size = if ([string]::IsNullOrEmpty($page_size)) { 50 } else { $page_size }
	foreach ($key in @($devices.Keys)) {
		$page = 0
		while ($true) {
			$contents = Invoke-UnimusGet "devices/$key/backups?size=$size&page=$page"
			$items = @($contents.data)
			foreach ($b in $items) {
				$date = Format-BackupDate $b.validSince
				Save-Backup $key $date $b.bytes $b.type
				$backupCount++
			}
			if ($items.Count -eq 0) { break }
			$page++
		}
	}
	Write-EchoGreen "$backupCount backups exported"
}

function Get-LatestBackups {
	$backupCount = 0
	$size = if ([string]::IsNullOrEmpty($page_size)) { 50 } else { $page_size }
	$page = 0
	while ($true) {
		$contents = Invoke-UnimusGet "devices/backups/latest?size=$size&page=$page"
		$items = @($contents.data)
		foreach ($b in $items) {
			$date = Format-BackupDate $b.backup.validSince
			Save-Backup $b.deviceId $date $b.backup.bytes $b.backup.type
			$backupCount++
		}
		if ($items.Count -eq 0) { break }
		$page++
	}
	Write-EchoGreen "$backupCount backups exported"
}

# --- git export -----------------------------------------------------------

function Push-ToGit {
	Set-Location -LiteralPath $backup_dir
	$inside = (& git rev-parse --is-inside-work-tree 2>$null)
	if (-not $inside) {
		& git init
		& git config user.email $git_email
		& git config user.name $git_username
		& git add .
		& git commit -m 'Initial Commit'
		switch ($git_server_protocol) {
			'ssh' {
				$knownHosts = "$HOME/.ssh/known_hosts"
				$sshDir = Split-Path -Parent $knownHosts
				if (-not [IO.Directory]::Exists($sshDir)) { [IO.Directory]::CreateDirectory($sshDir) | Out-Null }
				& ssh-keyscan -H $git_server_address *>> $knownHosts
				# SSH may or may not require a password.
				if ([string]::IsNullOrEmpty($git_password)) {
					& git remote add origin "ssh://${git_username}@${git_server_address}/${git_repo_name}"
				} else {
					& git remote add origin "ssh://${git_username}:${git_password}@${git_server_address}/${git_repo_name}"
				}
				Invoke-ErrorCheck $LASTEXITCODE 'Failed to add git repo'
			}
			'http' {
				& git remote add origin "http://${git_username}:${git_password}@${git_server_address}:${git_port}/${git_repo_name}"
				Invoke-ErrorCheck $LASTEXITCODE 'Failed to add git repo'
			}
			'https' {
				& git remote add origin "https://${git_username}:${git_password}@${git_server_address}:${git_port}/${git_repo_name}"
				Invoke-ErrorCheck $LASTEXITCODE 'Failed to add git repo'
			}
			default {
				Write-EchoRed 'Invalid setting for git_server_protocol'
				exit 2
			}
		}
		& git push -u origin $git_branch *>> $log
		Invoke-ErrorCheck $LASTEXITCODE 'Failed to add branch'
		& git push *>> $log
		Invoke-ErrorCheck $LASTEXITCODE 'Failed to push to git'
	} else {
		& git add --all
		& git commit -m "Unimus Git Extractor $((Get-Date).ToString('MMM-dd-yy HH:mm'))"
		& git push
		Invoke-ErrorCheck $LASTEXITCODE 'Failed to push to git'
	}
	Set-Location -LiteralPath $script_dir
}

# --- config ---------------------------------------------------------------

# Abort if a required variable is empty.
function Test-Var($value, $name) {
	if ([string]::IsNullOrEmpty($value)) {
		Write-EchoRed "$name is not set in unimus-backup-exporter.env"
		exit 2
	}
}

function Import-Variables {
	$envFile = "$script_dir/unimus-backup-exporter.env"
	foreach ($line in [IO.File]::ReadAllLines($envFile)) {
		$trimmed = $line.Trim()
		if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
		$eq = $trimmed.IndexOf('=')
		if ($eq -lt 1) { continue }
		$name = $trimmed.Substring(0, $eq).Trim()
		$val = $trimmed.Substring($eq + 1).Trim()
		if ($val.Length -ge 2 -and (
				($val.StartsWith('"') -and $val.EndsWith('"')) -or
				($val.StartsWith("'") -and $val.EndsWith("'")))) {
			$val = $val.Substring(1, $val.Length - 2)
		}
		Set-Variable -Scope Script -Name $name -Value $val
	}

	Test-Var $unimus_server_address 'unimus_server_address'
	Test-Var $unimus_api_key 'unimus_api_key'
	Test-Var $backup_type 'backup_type'
	Test-Var $export_type 'export_type'
	if ($export_type -eq 'git') {
		Test-Var $git_username 'git_username'
		# A password is only required for http/https remotes.
		if ($git_server_protocol -eq 'http' -or $git_server_protocol -eq 'https') {
			if ([string]::IsNullOrEmpty($git_password)) {
				Write-EchoRed 'Please Provide a git password'
				exit 2
			}
		}
		Test-Var $git_email 'git_email'
		Test-Var $git_server_protocol 'git_server_protocol'
		Test-Var $git_server_address 'git_server_address'
		Test-Var $git_port 'git_port'
		Test-Var $git_repo_name 'git_repo_name'
		Test-Var $git_branch 'git_branch'
	}
}

# --- main -----------------------------------------------------------------

function Invoke-Main {
	$script:SCRIPT_VERSION = '1.1.0'

	$script:script_dir = $PSScriptRoot
	Set-Location -LiteralPath $script_dir
	$script:backup_dir = "$script_dir/backups"
	$script:devices = @{}

	if (-not [IO.Directory]::Exists($backup_dir)) {
		[IO.Directory]::CreateDirectory($backup_dir) | Out-Null
	}

	$script:log = "$script_dir/unimus-backup-exporter.log"
	[IO.File]::AppendAllText($log, "Log File - $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))`n")

	Test-LatestVersion
	Import-Variables

	$status = Get-UnimusStatus
	if ($status -eq 'OK') {
		Write-EchoGreen 'Getting device data'
		Get-AllDevices

		switch ($backup_type) {
			'latest' {
				Write-EchoGreen 'Exporting latest backups'
				Get-LatestBackups
				Write-EchoGreen 'Export successful'
			}
			'all' {
				Write-EchoGreen 'Exporting all backups'
				Get-AllBackups
				Write-EchoGreen 'Export successful'
			}
		}

		if ($export_type -eq 'git') {
			Write-EchoGreen 'Pushing to git'
			Push-ToGit
			Write-EchoGreen 'Push successful'
		}
	} else {
		if ([string]::IsNullOrEmpty($status)) {
			Write-EchoRed 'Unable to connect to unimus server'
			exit 2
		} else {
			Write-EchoRed "Unimus server status: $status"
		}
	}
	Write-EchoGreen 'Script finished'
}

# Run main unless the script is being dot-sourced (e.g. by the Pester tests).
if ($MyInvocation.InvocationName -ne '.') {
	Invoke-Main
}
