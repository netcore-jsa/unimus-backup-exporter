# Pester unit tests for the PowerShell version (per-language layer, mirrors the
# bats units). The shared cross-implementation coverage lives in the Python e2e + git
# harness, run against it via EXPORTER_CMD="pwsh ./unimus-backup-exporter.ps1".
#
# Run:  pwsh -c 'Invoke-Pester tests/unit/pwsh'

BeforeAll {
	$script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '../../../unimus-backup-exporter.ps1')).Path
	# Dot-source: defines the functions; the main guard keeps Invoke-Main from running.
	. $ScriptPath
}

Describe 'Save-Backup' {
	BeforeEach {
		$global:tmp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
		[IO.Directory]::CreateDirectory($global:tmp) | Out-Null
		$global:backup_dir = $global:tmp
		$global:log = Join-Path $global:tmp 'log'
		$global:devices = @{ '1' = '10.0.0.1'; '2' = 'switch01.lab' }
		$global:separator = $null
	}
	AfterEach {
		Remove-Item -Recurse -Force $global:tmp -ErrorAction SilentlyContinue
	}

	It 'writes a TEXT backup with .txt extension and decoded content' {
		$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("hello world`n"))
		Save-Backup 1 '2021-01-01-00-00-00-UTC' $b64 'TEXT'
		$f = "$global:backup_dir/10.0.0.1 - 1/Backup 10.0.0.1 2021-01-01-00-00-00-UTC 1.txt"
		[IO.File]::Exists($f) | Should -BeTrue
		[IO.File]::ReadAllText($f) | Should -Be "hello world`n"
	}

	It 'writes a BINARY backup with .bin extension' {
		$b64 = [Convert]::ToBase64String([byte[]](0..15))
		Save-Backup 2 '2021-04-01-00-00-00-UTC' $b64 'BINARY'
		$f = "$global:backup_dir/switch01.lab - 2/Backup switch01.lab 2021-04-01-00-00-00-UTC 2.bin"
		[IO.File]::Exists($f) | Should -BeTrue
		[IO.File]::ReadAllBytes($f) | Should -Be ([byte[]](0..15))
	}

	It 'is idempotent: does not overwrite an existing backup' {
		$f = "$global:backup_dir/10.0.0.1 - 1/Backup 10.0.0.1 2021-01-01-00-00-00-UTC 1.txt"
		Save-Backup 1 '2021-01-01-00-00-00-UTC' ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("first`n"))) 'TEXT'
		Save-Backup 1 '2021-01-01-00-00-00-UTC' ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("second`n"))) 'TEXT'
		[IO.File]::ReadAllText($f) | Should -Be "first`n"
	}

	It 'honors a custom separator (issue #8)' {
		$global:separator = '_'
		$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("x`n"))
		Save-Backup 1 '2021-01-01-00-00-00-UTC' $b64 'TEXT'
		$f = "$global:backup_dir/10.0.0.1_-_1/Backup_10.0.0.1_2021-01-01-00-00-00-UTC_1.txt"
		[IO.File]::Exists($f) | Should -BeTrue
	}
}

Describe 'Format-BackupDate' {
	It 'produces a UTC, colon-free timestamp (Windows-safe)' {
		Format-BackupDate 1609459200 | Should -Be '2021-01-01-00-00-00-UTC'
	}
}

Describe 'Test-Var' {
	It 'aborts (exit 2) on an empty value' {
		& pwsh -NoProfile -Command ". '$script:ScriptPath'; `$global:log = [IO.Path]::GetTempFileName(); Test-Var '' 'unimus_api_key'" *> $null
		$LASTEXITCODE | Should -Be 2
	}
	It 'passes a non-empty value' {
		& pwsh -NoProfile -Command ". '$script:ScriptPath'; `$global:log = [IO.Path]::GetTempFileName(); Test-Var 'x' 'unimus_api_key'" *> $null
		$LASTEXITCODE | Should -Be 0
	}
}

Describe 'Invoke-ErrorCheck' {
	It 'exits with the captured code on failure' {
		& pwsh -NoProfile -Command ". '$script:ScriptPath'; `$global:log = [IO.Path]::GetTempFileName(); Invoke-ErrorCheck 3 'boom'" *> $null
		$LASTEXITCODE | Should -Be 3
	}
	It 'is a no-op on success' {
		& pwsh -NoProfile -Command ". '$script:ScriptPath'; `$global:log = [IO.Path]::GetTempFileName(); Invoke-ErrorCheck 0 'ok'" *> $null
		$LASTEXITCODE | Should -Be 0
	}
}

Describe 'Test-LatestVersion' {
	BeforeEach {
		$global:log = [IO.Path]::GetTempFileName()
		$global:SCRIPT_VERSION = '1.1.0'
	}
	It 'warns when the remote release is newer' {
		Mock Invoke-RestMethod { [pscustomobject]@{ tag_name = 'v99.1.0' } }
		Mock Write-EchoYellow {}
		Test-LatestVersion
		Should -Invoke Write-EchoYellow -Times 1 -ParameterFilter { $message -like '*older version*' }
	}
	It 'stays quiet when the local version matches' {
		Mock Invoke-RestMethod { [pscustomobject]@{ tag_name = 'v1.1.0' } }
		Mock Write-EchoYellow {}
		Test-LatestVersion
		Should -Invoke Write-EchoYellow -Times 0
	}
}

Describe 'Get-AllDevices' {
	BeforeEach {
		$global:log = [IO.Path]::GetTempFileName()
		$global:devices = @{}
		$global:device_name_field = $null
		# page 0 returns two devices (device 2 has an empty description), later pages empty.
		Mock Invoke-UnimusGet {
			if ($path -like '*page=0') {
				[pscustomobject]@{ data = @(
						[pscustomobject]@{ id = 1; address = '10.0.0.1'; description = 'router1' },
						[pscustomobject]@{ id = 2; address = '10.0.0.2'; description = '' }) }
			} else {
				[pscustomobject]@{ data = @() }
			}
		}
	}

	It 'defaults to naming by address' {
		Get-AllDevices | Out-Null
		$global:devices['1'] | Should -Be '10.0.0.1'
		$global:devices['2'] | Should -Be '10.0.0.2'
	}

	It 'names by a custom field, falling back to address when empty (issue #11)' {
		$global:device_name_field = 'description'
		Get-AllDevices | Out-Null
		$global:devices['1'] | Should -Be 'router1'      # description used
		$global:devices['2'] | Should -Be '10.0.0.2'     # empty description -> address fallback
	}
}
