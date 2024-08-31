#!/usr/bin/bash

function print_help {
    cat <<EOM 
Setup environment for PostgreSQL development.
Usage: $0

Options:
    -h, --help          Print this help message
EOM
}

if [ "$1" ]; then
    case "$1" in
    --help|-h)
        print_help
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
fi

set -e
cd "$(dirname ${BASH_SOURCE[0]:-$0})/.."

CFLAGS="-O0 -g $CFLAGS"
CPPFLAGS="-O0 -g $CPPFLAGS"
INSTALL_PATH="$PWD/build"

./configure --prefix="$INSTALL_PATH" \
            --enable-debug \
            --enable-cassert \
            --enable-tap-tests \
            --enable-depend \
            CFLAGS="$CFLAGS" \
            CPPFLAGS="$CPPFLAGS"

PSQLRC_FILE="${PWD}/dev/.psqlrc"
cat <<EOF >"./dev/pg_dev_config.sh"
export PGINSTDIR="$INSTALL_PATH"
export PGDATA="$INSTALL_PATH/data"
export PGHOST="localhost"
export PGPORT="5432"
export PGUSER="postgres"
export PGDATABASE="postgres"
export PATH="$INSTALL_PATH/bin:\$PATH"
LD_LIBRARY_PATH="\${LD_LIBRARY_PATH:-''}"
export LD_LIBRARY_PATH="\$PGINSTDIR/lib:\$LD_LIBRARY_PATH"
export PSQLRC="${PSQLRC_FILE}"
EOF

chmod +x "./dev/pg_dev_config.sh"

cat <<EOF >"$PSQLRC_FILE"
\o ${PWD}/dev/backend.pid
select pg_backend_pid() as pid
\gset
\qecho :pid
\o
select pg_backend_pid();
EOF
