FROM library/mongo:4.2-windowsservercore-1809 AS servercore
FROM mcr.microsoft.com/windows/nanoserver:1809 AS nanoserver

COPY --from=servercore /mongodb /mongodb
COPY --from=servercore /Windows/System32/MSVCP140.dll /Windows/System32/MSVCP140.dll
COPY --from=servercore /Windows/System32/vcruntime140.dll /Windows/System32/vcruntime140.dll

ENV PATH="C:\Windows\system32;C:\Windows;C:\mongodb\bin;"

VOLUME C:\\data\\db C:\\data\\configdb

EXPOSE 27017
CMD ["mongod", "--bind_ip_all"]
