#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM mcr.microsoft.com/windows/servercore:ltsc2016

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop';"]

# http://docs.mongodb.org/master/release-notes/4.4/
ENV MONGO_VERSION 4.4.6
# 05/07/2021, https://github.com/mongodb/mongo/tree/72e66213c2c3eab37d9358d5e78ad7f5c1d0d0d7

ENV MONGO_DOWNLOAD_URL https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-4.4.6-signed.msi
ENV MONGO_DOWNLOAD_SHA256=ede50e8f8d8c9d23a8ca2cc1c96cdb9bcc1f617930e8bd1d46f21d95d0b555f8

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
			'ADDLOCAL=Client,MiscellaneousTools,Router,ServerNoService' \
		); \
	if (-Not (Test-Path C:\mongodb\bin\mongo.exe -PathType Leaf)) { \
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
	Write-Host '  mongo --version'; mongo --version; \
	Write-Host '  mongod --version'; mongod --version; \
	\
	Write-Host 'Removing ...'; \
	Remove-Item C:\windows\installer\*.msi -Force; \
	Remove-Item mongo.msi -Force; \
	\
	Write-Host 'Complete.';

VOLUME C:\\data\\db C:\\data\\configdb

# TODO docker-entrypoint.ps1 ? (for "docker run <image> --flag --flag --flag")

EXPOSE 27017
CMD ["mongod", "--bind_ip_all"]
