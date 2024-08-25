#!/usr/bin/bash

FULL=""
BUILD=""

while [[ "$1" ]]; do
    ARG="$1"
    case $ARG in
        --full)
            FULL="1"
            ;;
        --build)
            BUILD="1"
            ;;
        *)
            echo "Unknown argument: $ARG"
            exit 1
            ;;
    esac
    shift
done

source "$(dirname ${BASH_SOURCE[0]:-$0})/utils.sh"

if [[ "$BUILD" ]]; then
    make clean
fi

if [[ "$FULL" ]]; then
    make distclean
fi
