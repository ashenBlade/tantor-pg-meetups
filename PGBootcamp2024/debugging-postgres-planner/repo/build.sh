#!/usr/bin/bash

set -ex
source "$(dirname ${BASH_SOURCE[0]:-$0})/utils.sh"
source_config_file

THREADS=""
while [[ -n "$1" ]]; do
    ARG="$1"
    case $ARG in
    -j)
        shift
        THREADS="$1"
        ;;
    --jobs=*)
        THREADS="${$1#*=}"
        ;;
    esac
    shift
done


if [[ -n "$THREADS" ]]; then
    THREADS="-j $THREADS"
fi

make $THREADS
make install
source "$CONFIG_FILE"
make install-world-bin
