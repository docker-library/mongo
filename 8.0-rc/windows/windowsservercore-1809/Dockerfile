#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM mcr.microsoft.com/windows/servercore:1809

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop';"]

# https://docs.mongodb.org/master/release-notes/8.0/
ENV MONGO_VERSION 8.0.0-rc4
# 04/30/2024, https://github.com/mongodb/mongo/tree/afbb110c5dbea6ec8c775acbecaadb975cffd4d6

ENV MONGO_DOWNLOAD_URL https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-8.0.0-rc4-signed.msi
ENV MONGO_DOWNLOAD_SHA256=27e4d4a3912e2639a5bc56a4bc2417eb7d32e23c2be785cdc3f767585d884d11

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
