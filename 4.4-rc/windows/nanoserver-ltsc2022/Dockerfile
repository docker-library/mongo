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

COPY --from=mongo:4.4.12-rc0-windowsservercore-ltsc2022 \
	C:\\Windows\\System32\\msvcp140.dll \
	C:\\Windows\\System32\\vcruntime140.dll \
	C:\\Windows\\System32\\vcruntime140_1.dll \
	C:\\Windows\\System32\\

# http://docs.mongodb.org/master/release-notes/4.4/
ENV MONGO_VERSION 4.4.12-rc0
# 12/30/2021, https://github.com/mongodb/mongo/tree/1c02e51ffdc45678cc42b21ab1f27388649505a4

COPY --from=mongo:4.4.12-rc0-windowsservercore-ltsc2022 C:\\mongodb C:\\mongodb
RUN mongo --version && mongod --version

VOLUME C:\\data\\db C:\\data\\configdb

EXPOSE 27017
CMD ["mongod", "--bind_ip_all"]
