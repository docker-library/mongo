#!/bin/bash
set -e

if [ "${1:0:1}" = '-' ]; then
	set -- mongod "$@"
fi

# allow the container to be started with `--user`
# all mongo* commands should be dropped to the correct user
if [[ "$1" == mongo* ]] && [ "$(id -u)" = '0' ]; then
	if [ "$1" = 'mongod' ]; then
		chown -R mongodb /data/configdb /data/db
	fi
	chown --dereference mongodb /dev/stdout /dev/stderr
	exec gosu mongodb "$BASH_SOURCE" "$@"
fi

# you should use numactl to start your mongod instances, including the config servers, mongos instances, and any clients.
# https://docs.mongodb.com/manual/administration/production-notes/#configuring-numa-on-linux
if [[ "$1" == mongo* ]]; then
	numa='numactl --interleave=all'
	if $numa true &> /dev/null; then
		set -- $numa "$@"
	fi
fi

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

if [ "$1" = 'mongod' ]; then
	file_env 'MONGO_INITDB_ROOT_USERNAME'
	file_env 'MONGO_INITDB_ROOT_PASSWORD'
	if [ "$MONGO_INITDB_ROOT_USERNAME" ] && [ "$MONGO_INITDB_ROOT_PASSWORD" ]; then
		set -- "$@" --auth
	fi

	# check for a few known paths (to determine whether we've already initialized and should thus skip our initdb scripts)
	definitelyAlreadyInitialized=
	for path in \
		/data/db/WiredTiger \
		/data/db/journal \
		/data/db/local.0 \
		/data/db/storage.bson \
	; do
		if [ -e "$path" ]; then
			definitelyAlreadyInitialized="$path"
			break
		fi
	done

	if [ -z "$definitelyAlreadyInitialized" ]; then
		"$@" --fork --bind_ip 127.0.0.1 --logpath "/proc/$$/fd/1"

		mongo=( mongo --quiet )

		# check to see that "mongod" actually did start up (catches "--help", "--version", MongoDB 3.2 being silly, etc)
		if ! "${mongo[@]}" 'admin' --eval 'quit(0)' &> /dev/null; then
			echo >&2
			echo >&2 'error: mongod does not appear to have started up -- perhaps it had an error?'
			echo >&2
			exit 1
		fi

		if [ "$MONGO_INITDB_ROOT_USERNAME" ] && [ "$MONGO_INITDB_ROOT_PASSWORD" ]; then
			rootAuthDatabase='admin'

			"${mongo[@]}" "$rootAuthDatabase" <<-EOJS
				db.createUser({
					user: $(jq --arg 'user' "$MONGO_INITDB_ROOT_USERNAME" --null-input '$user'),
					pwd: $(jq --arg 'pwd' "$MONGO_INITDB_ROOT_PASSWORD" --null-input '$pwd'),
					roles: [ { role: 'root', db: $(jq --arg 'db' "$rootAuthDatabase" --null-input '$db') } ]
				})
			EOJS

			mongo+=(
				--username="$MONGO_INITDB_ROOT_USERNAME"
				--password="$MONGO_INITDB_ROOT_PASSWORD"
				--authenticationDatabase="$rootAuthDatabase"
			)
		fi

		export MONGO_INITDB_DATABASE="${MONGO_INITDB_DATABASE:-test}"

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh) echo "$0: running $f"; . "$f" ;;
				*.js) echo "$0: running $f"; "${mongo[@]}" "$MONGO_INITDB_DATABASE" "$f"; echo ;;
				*)    echo "$0: ignoring $f" ;;
			esac
			echo
		done

		"$@" --shutdown

		echo
		echo 'MongoDB init process complete; ready for start up.'
		echo
	fi

	unset MONGO_INITDB_ROOT_USERNAME
	unset MONGO_INITDB_ROOT_PASSWORD
	unset MONGO_INITDB_DATABASE
fi

exec "$@"
