#!/usr/bin/bash

set -ex
source "$(dirname ${BASH_SOURCE[0]:-$0})/utils.sh"
source_config_file

RUN_DB=""
RUN_PSQL=""
STOP_DB=""
INIT_DB=""

while [[ -n "$1" ]]; do
    ARG="$1"
    case "$ARG" in
        --init-db)
            INIT_DB="1"
            ;;
        --run-db)
            RUN_DB="1"
            ;;
        --psql)
            RUN_PSQL="1"
            ;;
        --stop-db)
            STOP_DB="1"
            ;;
        *)
            echo "Unknown argument: $ARG"
            exit 1
            ;;
    esac
    shift
done

# All env variables already setup for current installation

if [[ "$INIT_DB" ]]; then
    initdb -U $PGUSER || true
fi

if [[ "$RUN_DB" ]]; then
    # Not 0 exit code can mean DB already running - do not exit script with error
    pg_ctl start -o '-k ""' || true
fi

if [[ "$RUN_PSQL" ]]; then
    psql
    rm ./dev/backend.pid
fi

if [[ "$STOP_DB" ]]; then
    pg_ctl stop || true
fi