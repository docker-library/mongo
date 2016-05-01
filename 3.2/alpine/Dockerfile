FROM alpine:3.3

ENV MONGO_MAJOR 3.2
ENV MONGO_VERSION 3.2.1

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN adduser -D mongodb

RUN apk add --no-cache --virtual .deps openssl \
	&& apk add --no-cache --virtual .build-deps curl tar scons g++ openssl-dev \
	# grab gosu for easy step-down from root
	&& curl -o /usr/local/bin/gosu -fsSL "https://github.com/tianon/gosu/releases/download/1.7/gosu-amd64" \
	&& chmod +x /usr/local/bin/gosu

RUN curl -SL "https://fastdl.mongodb.org/src/mongodb-src-r$MONGO_VERSION.tar.gz" -o mongo.tar.gz \
	&& mkdir mongo \
	&& tar -xf mongo.tar.gz -C mongo --strip-components=1 \
	&& rm mongo.tar.gz

RUN cd mongo \
	&& wget \
	    http://git.alpinelinux.org/cgit/aports/plain/testing/mongodb/40-fix-elf-native-class.patch \
	    https://patch-diff.githubusercontent.com/raw/mongodb/mongo/pull/1059.patch \
	&& patch -p1 < 40-fix-elf-native-class.patch \
	&& patch -p1 < 1059.patch \
	&& scons core -j$(getconf _NPROCESSORS_ONLN) --ssl --disable-warnings-as-errors  \
	&& scons --prefix=/opt/mongo install \
	&& cd .. \
	&& rm -r mongo \
	&& apk del .build-deps

VOLUME /data/db

COPY docker-entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 27017
CMD ["mongod"]
