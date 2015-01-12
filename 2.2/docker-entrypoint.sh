#!/bin/bash
set -e

if [ "${1:0:1}" = '-' ]; then
	set -- mongod "$@"
fi

if [ "$1" = 'mongod' ]; then
	chown -R mongodb /data/db

	NUMA_CMD="numactl --interleave=all"
	if ($NUMA_CMD true &>/dev/null) ; then
		set -- $NUMA_CMD "$@"
	fi

	exec gosu mongodb "$@"
fi

exec "$@"
