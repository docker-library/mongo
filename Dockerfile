FROM debian:jessie

RUN apt-get update && apt-get install -y build-essential scons libssl-dev

ADD . /usr/src/mongo
WORKDIR /usr/src/mongo

RUN scons -j"$(nproc)" all
RUN scons test
RUN scons install

VOLUME /var/lib/mongodb

EXPOSE 27017 28017
CMD ["mongod"]
