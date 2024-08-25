#!/usr/bin/bash

set -e
source "$(dirname ${BASH_SOURCE[0]:-$0})/utils.sh"
source_config_file

THREADS=""
FULL=""
BASE=""

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
        --base)
            BASE="1"
            ;;
        --full)
            FULL="1"    
            ;;
    esac
    shift
done

if [[ "$THREADS" ]]; then
    THREADS="-j $THREADS"
fi

if [[ "$BASE" ]]; then
    make check $THREADS
fi

if [[ "$FULL" ]]; then
    make check-world $THREADS
fi
