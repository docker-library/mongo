#!/bin/bash
set -Eeuo pipefail

if [ "${1:0:1}" = '-' ]; then
	set -- mongod "$@"
fi

originalArgOne="$1"

# allow the container to be started with `--user`
# all mongo* commands should be dropped to the correct user
if [[ "$originalArgOne" == mongo* ]] && [ "$(id -u)" = '0' ]; then
	if [ "$originalArgOne" = 'mongod' ]; then
		chown -R mongodb /data/configdb /data/db
	fi

	# make sure we can write to stdout and stderr as "mongodb"
	# (for our "initdb" code later; see "--logpath" below)
	chown --dereference mongodb "/proc/$$/fd/1" "/proc/$$/fd/2" || :
	# ignore errors thanks to https://github.com/docker-library/mongo/issues/149

	exec gosu mongodb "$BASH_SOURCE" "$@"
fi

# you should use numactl to start your mongod instances, including the config servers, mongos instances, and any clients.
# https://docs.mongodb.com/manual/administration/production-notes/#configuring-numa-on-linux
if [[ "$originalArgOne" == mongo* ]]; then
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

# see https://github.com/docker-library/mongo/issues/147 (mongod is picky about duplicated arguments)
_mongod_hack_have_arg() {
	local checkArg="$1"; shift
	local arg
	for arg; do
		case "$arg" in
			"$checkArg"|"$checkArg"=*)
				return 0
				;;
		esac
	done
	return 1
}
declare -a mongodHackedArgs
# _mongod_hack_ensure_arg '--some-arg' "$@"
# set -- "${mongodHackedArgs[@]}"
_mongod_hack_ensure_arg() {
	local ensureArg="$1"; shift
	mongodHackedArgs=( "$@" )
	if ! _mongod_hack_have_arg "$ensureArg" "$@"; then
		mongodHackedArgs+=( "$ensureArg" )
	fi
}
# _mongod_hack_ensure_arg_val '--some-arg' 'some-val' "$@"
# set -- "${mongodHackedArgs[@]}"
_mongod_hack_ensure_arg_val() {
	local ensureArg="$1"; shift
	local ensureVal="$1"; shift
	mongodHackedArgs=()
	while [ "$#" -gt 0 ]; do
		local arg="$1"; shift
		case "$arg" in
			"$ensureArg")
				shift # also skip the value
				continue
				;;
			"$ensureArg"=*)
				# value is already included
				continue
				;;
		esac
		mongodHackedArgs+=( "$arg" )
	done
	mongodHackedArgs+=( "$ensureArg" "$ensureVal" )
}
# TODO what do to about "--config" ? :(

if [ "$originalArgOne" = 'mongod' ]; then
	file_env 'MONGO_INITDB_ROOT_USERNAME'
	file_env 'MONGO_INITDB_ROOT_PASSWORD'
	# pre-check a few factors to see if it's even worth bothering with initdb
	shouldPerformInitdb=
	if [ "$MONGO_INITDB_ROOT_USERNAME" ] && [ "$MONGO_INITDB_ROOT_PASSWORD" ]; then
		# if we have a username/password, let's set "--auth"
		_mongod_hack_ensure_arg '--auth' "$@"
		set -- "${mongodHackedArgs[@]}"
		shouldPerformInitdb='true'
	elif [ "$MONGO_INITDB_ROOT_USERNAME" ] || [ "$MONGO_INITDB_ROOT_PASSWORD" ]; then
		cat >&2 <<-'EOF'

			error: missing 'MONGO_INITDB_ROOT_USERNAME' or 'MONGO_INITDB_ROOT_PASSWORD'
			       both must be specified for a user to be created

		EOF
		exit 1
	fi

	if [ -z "$shouldPerformInitdb" ]; then
		# if we've got any /docker-entrypoint-initdb.d/* files to parse later, we should initdb
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh|*.js) # this should match the set of files we check for below
					shouldPerformInitdb="$f"
					break
					;;
			esac
		done
	fi

	# check for a few known paths (to determine whether we've already initialized and should thus skip our initdb scripts)
	if [ -n "$shouldPerformInitdb" ]; then
		for path in \
			/data/db/WiredTiger \
			/data/db/journal \
			/data/db/local.0 \
			/data/db/storage.bson \
		; do
			if [ -e "$path" ]; then
				shouldPerformInitdb=
				break
			fi
		done
	fi

	if [ -n "$shouldPerformInitdb" ]; then
		if _mongod_hack_have_arg --config "$@"; then
			echo >&2
			echo >&2 'warning: database is not yet initialized, and "--config" is specified'
			echo >&2 '  the initdb database startup might fail as a result!'
			echo >&2
		fi

		pidfile="$(mktemp)"
		trap "rm -f '$pidfile'" EXIT

		_mongod_hack_ensure_arg_val --bind_ip 127.0.0.1 "$@"
		_mongod_hack_ensure_arg_val --port 27017 "${mongodHackedArgs[@]}"

		sslMode="$(_mongod_hack_have_arg '--sslPEMKeyFile' "$@" && echo 'allowSSL' || echo 'disabled')" # "BadValue: need sslPEMKeyFile when SSL is enabled" vs "BadValue: need to enable SSL via the sslMode flag when using SSL configuration parameters"
		_mongod_hack_ensure_arg_val --sslMode "$sslMode" "${mongodHackedArgs[@]}"

		if stat "/proc/$$/fd/1" > /dev/null && [ -w "/proc/$$/fd/1" ]; then
			# https://github.com/mongodb/mongo/blob/38c0eb538d0fd390c6cb9ce9ae9894153f6e8ef5/src/mongo/db/initialize_server_global_state.cpp#L237-L251
			# https://github.com/docker-library/mongo/issues/164#issuecomment-293965668
			_mongod_hack_ensure_arg_val --logpath "/proc/$$/fd/1" "${mongodHackedArgs[@]}"
		else
			echo >&2 "warning: initdb logs cannot write to '/proc/$$/fd/1', so they are in '/data/db/docker-initdb.log' instead"
			_mongod_hack_ensure_arg_val --logpath /data/db/docker-initdb.log "${mongodHackedArgs[@]}"
		fi
		_mongod_hack_ensure_arg --logappend "${mongodHackedArgs[@]}"

		_mongod_hack_ensure_arg_val --pidfilepath "$pidfile" "${mongodHackedArgs[@]}"
		"${mongodHackedArgs[@]}" --fork

		mongo=( mongo --host 127.0.0.1 --port 27017 --quiet )

		# check to see that our "mongod" actually did start up (catches "--help", "--version", MongoDB 3.2 being silly, slow prealloc, etc)
		# https://jira.mongodb.org/browse/SERVER-16292
		tries=30
		while true; do
			if ! { [ -s "$pidfile" ] && ps "$(< "$pidfile")" &> /dev/null; }; then
				# bail ASAP if "mongod" isn't even running
				echo >&2
				echo >&2 "error: $originalArgOne does not appear to have stayed running -- perhaps it had an error?"
				echo >&2
				exit 1
			fi
			if "${mongo[@]}" 'admin' --eval 'quit(0)' &> /dev/null; then
				# success!
				break
			fi
			(( tries-- ))
			if [ "$tries" -le 0 ]; then
				echo >&2
				echo >&2 "error: $originalArgOne does not appear to have accepted connections quickly enough -- perhaps it had an error?"
				echo >&2
				exit 1
			fi
			sleep 1
		done

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

		"$@" --pidfilepath="$pidfile" --shutdown
		rm "$pidfile"
		trap - EXIT

		echo
		echo 'MongoDB init process complete; ready for start up.'
		echo
	fi

	unset "${!MONGO_INITDB_@}"
fi

exec "$@"
