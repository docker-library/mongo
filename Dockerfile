FROM debian:wheezy

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r mongodb && useradd -r -g mongodb mongodb

RUN apt-get update && apt-get install -y \
		build-essential \
		curl \
		libssl-dev \
		scons

RUN curl -o /usr/local/bin/gosu -SL 'https://github.com/tianon/gosu/releases/download/1.0/gosu' \
	&& chmod +x /usr/local/bin/gosu

ADD . /usr/src/mongo
RUN cp -a /usr/src/mongo /tmp/mongo-build \
	&& cd /tmp/mongo-build \
	&& scons -j"$(nproc)" --ssl core tools test install \
	&& cd / \
	&& rm -rf /tmp/mongo-build

VOLUME /data/db
ENTRYPOINT ["/usr/src/mongo/docker-entrypoint.sh"]

EXPOSE 27017
CMD ["mongod"]
