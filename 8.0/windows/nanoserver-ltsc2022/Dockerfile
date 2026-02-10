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

COPY --from=mongo:8.0.19-windowsservercore-ltsc2022 \
	C:\\Windows\\System32\\msvcp140.dll \
	C:\\Windows\\System32\\msvcp140_1.dll \
	C:\\Windows\\System32\\vcruntime140.dll \
	C:\\Windows\\System32\\vcruntime140_1.dll \
	C:\\Windows\\System32\\

# https://docs.mongodb.org/master/release-notes/8.0/
ENV MONGO_VERSION 8.0.19
# 02/03/2026, https://github.com/mongodb/mongo/tree/cc1adb6b0875cc3003854ac2489818e459686f0b

COPY --from=mongo:8.0.19-windowsservercore-ltsc2022 C:\\mongodb C:\\mongodb
RUN mongod --version

VOLUME C:\\data\\db C:\\data\\configdb

EXPOSE 27017
CMD ["mongod", "--bind_ip_all"]
