FROM alpine:3.3

ENV MONGO_VERSION 2.6.11

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN adduser -D mongodb

RUN apk add --no-cache --virtual .build-deps curl tar scons g++ \
	# grab gosu for easy step-down from root
	&& curl -o /usr/local/bin/gosu -fsSL "https://github.com/tianon/gosu/releases/download/1.7/gosu-amd64" \
	&& chmod +x /usr/local/bin/gosu \
	&& curl -SL "https://github.com/mongodb/mongo/archive/r$MONGO_VERSION.tar.gz" -o mongo.tgz \
	&& mkdir mongo \
	&& tar -xf mongo.tgz -C mongo --strip-components=1 \
	&& cd mongo \
	&& scons -j$(getconf _NPROCESSORS_ONLN) \
	&& scons --prefix=/opt/mongo install \
	&& rm mongo.tgz \
	&& apk del .build-deps

VOLUME /data/db

COPY docker-entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 27017
CMD ["mongod"]
