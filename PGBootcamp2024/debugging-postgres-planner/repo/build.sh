#!/usr/bin/bash

function print_help {
    cat <<EOM
Build PostgreSQL sources
Usage: $0 [-j N|--jobs=N]

    -j N, --jobs=N      Specify number of threads to use

Example: $0 -j 12
EOM
}

set -e

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

source "$(dirname ${BASH_SOURCE[0]:-$0})/utils.sh"
source_config_file

if [[ -n "$THREADS" ]]; then
    THREADS="-j $THREADS"
fi

make $THREADS
make install
source "$CONFIG_FILE"
make install-world-bin
