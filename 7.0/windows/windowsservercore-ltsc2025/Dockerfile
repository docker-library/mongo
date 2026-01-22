#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM mcr.microsoft.com/windows/servercore:ltsc2025

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop';"]

# https://docs.mongodb.org/master/release-notes/7.0/
ENV MONGO_VERSION 7.0.28
# 12/16/2025, https://github.com/mongodb/mongo/tree/cfc346c59d2cc3dbc903507fc642e22e3097f362

ENV MONGO_DOWNLOAD_URL https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-7.0.28-signed.msi
ENV MONGO_DOWNLOAD_SHA256=1b771743b269dde79eeef4fedd133b988b84dff343429c8b5bf1b158e0fbb3bf

ENV MONGOSH_REPO=mongodb-js/mongosh

RUN Write-Host ('Downloading {0} ...' -f $env:MONGO_DOWNLOAD_URL); \
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; \
	(New-Object System.Net.WebClient).DownloadFile($env:MONGO_DOWNLOAD_URL, 'mongo.msi'); \
	\
	if ($env:MONGO_DOWNLOAD_SHA256) { \
		Write-Host ('Verifying sha256 ({0}) ...' -f $env:MONGO_DOWNLOAD_SHA256); \
		if ((Get-FileHash mongo.msi -Algorithm sha256).Hash -ne $env:MONGO_DOWNLOAD_SHA256) { \
			Write-Host 'FAILED!'; \
			exit 1; \
		}; \
	}; \
	\
	Write-Host 'Installing ...'; \
# https://docs.mongodb.com/manual/tutorial/install-mongodb-on-windows/#install-mongodb-community-edition
	Start-Process msiexec -Wait \
		-ArgumentList @( \
			'/i', \
			'mongo.msi', \
			'/quiet', \
			'/qn', \
			'/l*v', 'install.log', \
# https://docs.mongodb.com/manual/tutorial/install-mongodb-on-windows-unattended/#run-the-windows-installer-from-the-windows-command-interpreter
			'INSTALLLOCATION=C:\mongodb', \
			'ADDLOCAL=MiscellaneousTools,Router,ServerNoService' \
		); \
	if (-Not (Test-Path C:\mongodb\bin\mongod.exe -PathType Leaf)) { \
		Write-Host 'Installer failed!'; \
		Get-Content install.log; \
		exit 1; \
	}; \
	Remove-Item install.log; \
	\
	$env:PATH = 'C:\mongodb\bin;' + $env:PATH; \
	[Environment]::SetEnvironmentVariable('PATH', $env:PATH, [EnvironmentVariableTarget]::Machine); \
	\
	Write-Host 'Verifying install ...'; \
	Write-Host '  mongod --version'; mongod --version; \
	\
	# -------------------------------
	# Install mongosh (latest MSI) + sha256 verification from GitHub asset digest
	# https://www.mongodb.com/docs/mongodb-shell/install/?operating-system=windows&windows-installation-method=msiexec
	# -------------------------------
	Write-Host 'Installing mongosh (latest release) ...'; \
	$Headers = @{ \
		'Accept'='application/vnd.github+json'; \
		'User-Agent'='PowerShell-Mongosh-Installer' \
	}; \
	$Api = ('https://api.github.com/repos/{0}/releases/latest' -f $env:MONGOSH_REPO); \
	$Release = Invoke-RestMethod -Uri $Api -Headers $Headers -Method Get; \
	$Asset = $Release.assets | Where-Object { $_.content_type -eq 'application/x-msi' } | Select-Object -First 1; \
	if (-not $Asset) { \
		Write-Host ('No MSI asset found in latest release for {0}' -f $env:MONGOSH_REPO); \
		exit 1; \
	}; \
	if (-not $Asset.digest) { \
		Write-Host ('MSI asset has no digest field to verify.'); \
		exit 1; \
	}; \
	$Digest = [string]$Asset.digest; \
	if ($Digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { \
		Write-Host ('Unexpected digest format: {0}' -f $Digest); \
		exit 1; \
	}; \
	$ExpectedSha = $Matches[1].ToLowerInvariant(); \
	$MongoshName = [string]$Asset.name; \
	$MongoshUrl  = [string]$Asset.browser_download_url; \
	Write-Host ('Downloading {0} ...' -f $MongoshUrl); \
	Invoke-WebRequest -Uri $MongoshUrl -Headers $Headers -OutFile $MongoshName; \
	$ActualSha = (Get-FileHash -Path $MongoshName -Algorithm SHA256).Hash.ToLowerInvariant(); \
	Write-Host ('Verifying mongosh sha256 ({0}) ...' -f $ExpectedSha); \
	if ($ActualSha -ne $ExpectedSha) { \
		Write-Host ('FAILED! expected={0} actual={1}' -f $ExpectedSha, $ActualSha); \
		exit 1; \
	}; \
	Write-Host 'Installing mongosh ...'; \
	Start-Process msiexec -Wait \
		-ArgumentList @( \
			'/i', \
			$MongoshName, \
			'/quiet', \
			'/qn', \
			'/l*v', \
			'mongosh-install.log' \
		); \
	if (-Not (Get-Command mongosh -ErrorAction SilentlyContinue)) { \
		Write-Host 'mongosh install may have failed!'; \
		if (Test-Path mongosh-install.log) { \
			Get-Content mongosh-install.log; \
		}; \
		exit 1; \
	}; \
	Write-Host '  mongosh --version'; mongosh --version; \
	if (Test-Path mongosh-install.log) { \
		Remove-Item mongosh-install.log -Force; \
	}; \
	Remove-Item $MongoshName -Force; \
	# -------------------------------
	\
	Write-Host 'Removing ...'; \
	Remove-Item C:\windows\installer\*.msi -Force; \
	Remove-Item mongo.msi -Force; \
	\
	Write-Host 'Complete.';

# TODO docker-entrypoint.ps1 ? (for "docker run <image> --flag --flag --flag")

VOLUME C:\\data\\db C:\\data\\configdb

EXPOSE 27017
CMD ["mongod", "--bind_ip_all"]
