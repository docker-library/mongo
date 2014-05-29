FROM debian:jessie

RUN apt-get update && apt-get install -y build-essential scons libssl-dev

ADD . /usr/src/mongo
WORKDIR /usr/src/mongo

RUN scons -j"$(nproc)" core tools

# the tests compile huge amounts of data, so we skip them for now
#RUN scons test

RUN scons install

VOLUME /data/db

EXPOSE 27017 28017
CMD ["mongod"]
