#!/bin/bash
set -e

if [ "${1:0:1}" = '-' ]; then
	set -- mongod "$@"
fi

CMD="numactl --interleave=all $@"
if ! numactl --show &> /dev/null ; then
    CMD="$@"
    echo "Warning: no NUMA support available on this system."
fi

if [ "$1" = 'mongod' ]; then
	chown -R mongodb /data/db
	exec gosu mongodb $CMD
fi

exec "$@"
