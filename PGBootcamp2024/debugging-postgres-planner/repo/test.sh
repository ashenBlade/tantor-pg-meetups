#!/usr/bin/bash

function print_help {
    cat <<EOM 
Run tests for PostgreSQL
Usage: $0 --regress|--full [-j N,--jobs=N]

    --regress - run regress tests (make check)
    --full - run all tests (make check-world)
    -j N | --jobs=N - specify number of threads for make

Example: $0 --regress -j 12
EOM
}

set -e

THREADS=""
FULL=""
REGRESS=""

while [[ -n "$1" ]]; do
    ARG="$1"
    case "$ARG" in
        -j)
            shift
            THREADS="$1"
            ;;
        --jobs=*)
            THREADS="${ARG#*=}"
            ;;
        --regress)
            REGRESS="1"
            ;;
        --full)
            FULL="1"    
            ;;
        --help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknnown argument: $ARG"
            exit 1
            ;;
    esac
    shift
done

source "$(dirname ${BASH_SOURCE[0]:-$0})/utils.sh"
source_config_file

if [[ "$THREADS" ]]; then
    THREADS="-j $THREADS"
fi

if [[ "$REGRESS" ]]; then
    make check $THREADS
fi

if [[ "$FULL" ]]; then
    make check-world $THREADS
fi
