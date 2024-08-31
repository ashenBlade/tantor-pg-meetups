#!/usr/bin/bash

source "$(dirname ${BASH_SOURCE[0]:-$0})/utils.sh"

PIDFILE="./dev/backend.pid"
if [ ! -f "$PIDFILE" ]; then
  >&2 echo "pid file $PIDFILE not found - make sure psql is running"
  exit 1
fi

PIDFILEDATA="$(head -n 1 $PIDFILE)"
if [ -z "$PIDFILEDATA" ]; then
  >&2 echo "pid file $PIDFILE is empty - make sure psql started without errors"
  exit 2
fi

if ! ps -p "$PIDFILEDATA" 2>&1 >/dev/null; then
    >&2 echo "no process found with pid $PIDFILEDATA"
    exit 3
fi

echo "$PIDFILEDATA"