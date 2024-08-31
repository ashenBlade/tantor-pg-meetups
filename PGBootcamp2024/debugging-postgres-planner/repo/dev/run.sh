#!/usr/bin/bash

function print_help {
    cat <<EOM
Run database and/or PSQL with settings for current installation.
Usage: $0 [--init-db] [--run-db] [--psql] [--stop-db]

    --init-db - initialize database files
    --run-db - run database using initialized database
    --psql - run psql
    --stop-db - stop running database

Example: $0 --run-db --psql --stop-db
EOM
}

set -e

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
        --help|-h) 
            print_help
            exit 0
            ;;
        *)
            echo "Unknown argument: $ARG"
            print_help
            exit 1
            ;;
    esac
    shift
done

source "$(dirname ${BASH_SOURCE[0]:-$0})/utils.sh"
source_config_file

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