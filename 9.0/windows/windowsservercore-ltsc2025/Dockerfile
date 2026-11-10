#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM mcr.microsoft.com/windows/servercore:ltsc2025

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop';"]

# https://docs.mongodb.org/master/release-notes/9.0/
ENV MONGO_VERSION 9.0.8
# 11/05/2026, https://github.com/mongodb/mongo/tree/115a0fe2dcd8edd5bacd4557bd2e741a8e080665

ENV MONGO_DOWNLOAD_URL https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-9.0.8-signed.msi
ENV MONGO_DOWNLOAD_SHA256=4841753f49c1e3e25d12ff63a049894b7d56e397f27f05303ccde5144a6ae060

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
	Write-Host 'Removing ...'; \
	Remove-Item C:\windows\installer\*.msi -Force; \
	Remove-Item mongo.msi -Force; \
	\
	Write-Host 'Complete.';

# TODO docker-entrypoint.ps1 ? (for "docker run <image> --flag --flag --flag")

VOLUME C:\\data\\db C:\\data\\configdb

EXPOSE 27017
CMD ["mongod", "--bind_ip_all"]
