#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM mcr.microsoft.com/windows/nanoserver:ltsc2022

SHELL ["cmd", "/S", "/C"]

# PATH isn't actually set in the Docker image, so we have to set it from within the container
USER ContainerAdministrator
RUN setx /m PATH "C:\mongodb\bin;%PATH%"
USER ContainerUser
# doing this first to share cache across versions more aggressively

COPY --from=mongo:8.0.17-windowsservercore-ltsc2022 \
	C:\\Windows\\System32\\msvcp140.dll \
	C:\\Windows\\System32\\msvcp140_1.dll \
	C:\\Windows\\System32\\vcruntime140.dll \
	C:\\Windows\\System32\\vcruntime140_1.dll \
	C:\\Windows\\System32\\

# https://docs.mongodb.org/master/release-notes/8.0/
ENV MONGO_VERSION 8.0.17
# 12/16/2025, https://github.com/mongodb/mongo/tree/b20e43625b72f4bb43cc15107f80ac966ae13b6d

ENV MONGOSH_REPO=mongodb-js/mongosh

COPY --from=mongo:8.0.17-windowsservercore-ltsc2022 C:\\mongodb C:\\mongodb

# Install mongosh on nanoserver too (explicitly invoke powershell)
RUN powershell -NoProfile -Command "$ErrorActionPreference='Stop'; \
	$Headers=@{ \
		'Accept'='application/vnd.github+json'; \
		'User-Agent'='PowerShell-Mongosh-Installer' \
	}; \
	$Api=('https://api.github.com/repos/{0}/releases/latest' -f $env:MONGOSH_REPO); \
	$Release=Invoke-RestMethod -Uri $Api -Headers $Headers -Method Get; \
	$Asset=$Release.assets | Where-Object { $_.content_type -eq 'application/x-msi' } | Select-Object -First 1; \
	if (-not $Asset) { \
		Write-Host ('No MSI asset found in latest release for {0}' -f $env:MONGOSH_REPO); \
		exit 1; \
	}; \
	if (-not $Asset.digest) { \
		Write-Host 'MSI asset has no digest field to verify.'; \
		exit 1; \
	}; \
	$Digest=[string]$Asset.digest; \
	if ($Digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { \
		Write-Host ('Unexpected digest format: {0}' -f $Digest); \
		exit 1; \
	}; \
	$ExpectedSha=$Matches[1].ToLowerInvariant(); \
	$MongoshName=[string]$Asset.name; \
	$MongoshUrl=[string]$Asset.browser_download_url; \
	Invoke-WebRequest -Uri $MongoshUrl -Headers $Headers -OutFile $MongoshName; \
	$ActualSha=(Get-FileHash -Path $MongoshName -Algorithm SHA256).Hash.ToLowerInvariant(); \
	if ($ActualSha -ne $ExpectedSha) { \
		Write-Host ('SHA256 mismatch: expected={0} actual={1}' -f $ExpectedSha,$ActualSha); \
		exit 1;\
	}; \
	Start-Process msiexec -Wait -ArgumentList @('/i',$MongoshName,'/quiet','/qn','/l*v','mongosh-install.log'); \
	if (-Not (Get-Command mongosh -ErrorAction SilentlyContinue)) { \
		if (Test-Path mongosh-install.log) { \
			Get-Content mongosh-install.log; \
		}; \
		Write-Host 'mongosh install may have failed.'; \
		exit 1; \
	}; \
	mongosh --version; \
	if (Test-Path mongosh-install.log) { \
		Remove-Item mongosh-install.log -Force; \
	}; \
	Remove-Item $MongoshName -Force;"

RUN mongod --version

VOLUME C:\\data\\db C:\\data\\configdb

EXPOSE 27017
CMD ["mongod", "--bind_ip_all"]
