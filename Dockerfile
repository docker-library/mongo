FROM debian:jessie

RUN apt-get update && apt-get install -y build-essential scons libssl-dev

# "--use-system" deps
RUN apt-get update && apt-get install -y \
		libboost-dev \
		libboost-filesystem-dev \
		libboost-program-options-dev \
		libboost-thread-dev \
		libgoogle-perftools-dev \
		libpcap-dev \
		libpcre++-dev \
		libsnappy-dev \
		libstemmer-dev \
		libv8-dev
ENV SCONS_OPTS --use-system-snappy --use-system-tcmalloc --use-system-pcre --use-system-boost --use-system-v8 --ssl

ADD . /usr/src/mongo
WORKDIR /usr/src/mongo

# the unstripped binaries and build artifacts are enormous, so we strip and
# remove them manually to help alleviate that huge layer being an issue
RUN scons -j"$(nproc)" $SCONS_OPTS core tools \
	&& find -maxdepth 1 -type f -executable -exec strip '{}' + \
	&& rm -rf build

# the tests compile huge amounts of data, so we skip them for now
#RUN scons $SCONS_OPTS test

# since we're stripping and removing build artifacts, we get to install
# manually too (since scons rightfully thinks we need to rebuild)
#RUN scons $SCONS_OPTS install
RUN find -maxdepth 1 -type f -executable -exec ln -v '{}' /usr/local/bin/ ';'

VOLUME /data/db

EXPOSE 27017 28017
CMD ["mongod"]
