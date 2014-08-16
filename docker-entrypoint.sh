#!/bin/bash
set -e

if [ "$1" = 'mongod' ]; then
	chown -R mongodb "/data/db"
	exec gosu mongodb "$@"
fi

exec "$@"
