#!/bin/bash
set -e

if [ "${1:0:1}" = '-' ]; then
	set -- mongod "$@"
fi

if [ "$1" = 'mongod' ]; then
	chown -R mongodb /data/db

	numa='numactl --interleave=all'
	if $numa true &> /dev/null; then
		set -- $numa "$@"
	fi

	# internal start of server in order to allow set-up using mongo client
	gosu mongodb mongod --fork --dbpath=/data/db --syslog

	for f in /docker-entrypoint-initdb.d/*; do
		case "$f" in
			*.sh)  echo "$0: running $f"; . "$f" ;;
			*.js)  echo "$0: running $f"; mongo --nodb "$f" && echo ;;
			*)     echo "$0: ignoring $f" ;;
		esac
	done

	# stop the temporary server daemon
	gosu mongodb mongod --shutdown --dbpath=/data/db

	exec gosu mongodb "$@"
fi

exec "$@"
