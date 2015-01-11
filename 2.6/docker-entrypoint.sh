#!/bin/bash
set -e

if [ "${1:0:1}" = '-' ]; then
	set -- mongod "$@"
fi

if [ "$1" = 'mongod' ]; then
	chown -R mongodb /data/db

	NUMA_CMD="numactl --interleave=all"
	if ! ($NUMA_CMD true >/dev/null 2>&1) ; then
		NUMA_CMD=
	fi

	exec gosu mongodb $NUMA_CMD "$@"
fi

exec "$@"
