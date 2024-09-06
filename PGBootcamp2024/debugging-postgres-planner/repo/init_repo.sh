#!/usr/bin/bash

function print_help {
    cat <<EOF
Repository initialization script. Used for 'Debugging PostgreSQL planner' presentation at PG BootCamp.
It:
    1) Downloads PostgreSQL 16.4 source files
    2) Sets up scripts and configuration files 
    3) Sets up VS Code (install extensions)
    4) Applies required patches for source files
    4) Runs setup script

Usage: $0 -f|--force

Options:

    -h|--help\t\t- Shows this help message
    -f|--force\t\t- Forces repository initialization.
                    Can be used when you want force reinstall files.

EOF
}

FORCE_MODE=""
HAS_GIT="1"

case "$1" in
-f|--force)
    FORCE_MODE="1"
    ;;
-h|--help)
    print_help
    exit 0;
    ;;
"")
    ;;
*)
    print_help
    exit 1
    ;;
esac

# Set cwd to ./repo
cd "$(dirname "${BASH_SOURCE[0]:-$0}")"

# Stop at first error
set -e

NEW_FILES="1"

# Download sources
if [ ! -d 'postgresql' ] || [ "$FORCE_MODE" ]; then
    if [ -d 'postgresql' ]; then
        echo "Removing old 'postgresql' directory"
        rm -rf "postgresql"
    fi
        
    if git --version >/dev/null 2>&1; then
        echo "Git detected. Downloading PostgreSQL source files using git"
        git clone https://git.postgresql.org/git/postgresql.git \
            --single-branch --branch=REL_16_4 postgresql 

    elif wget --version >/dev/null 2>&1 && tar --version >/dev/null 2>&1; then
        echo "Git NOT detected. Downloading PostgreSQL source files using wget from ftp.postgresql.org"
        wget -qO- https://ftp.postgresql.org/pub/source/v16.4/postgresql-16.4.tar.gz \
            | tar xvz postgresql-16.4
        mv postgresql-16.4 postgresql
        HAS_GIT=""
    else
        cat <<EOF
Failed to download PostgreSQL source files - no git or wget found.
Please download PostgreSQL 16.4 source files into 'postgresql' directory manually.

You can use:

wget -qO- https://ftp.postgresql.org/pub/source/v16.4/postgresql-16.4.tar.gz | tar xvf postgresql-16.4 && mv postgresql-16.4 postgresql

    or

git clone https://git.postgresql.org/git/postgresql.git --single-branch --branch=REL_16_4 postgresql
EOF
        exit 1
    fi
else
    echo "'postgresql' directory already exists. Skipping source files downloading"
    NEW_FILES=""
fi

# Setup dev scripts
echo "Copying development scripts into postgresql/dev"
cp -r dev postgresql/dev

# Applying patches
echo "Applying Constraint Exclusion setup patch"

cd postgresql
if [ "$HAS_GIT" ]; then
    git checkout src/backend/optimizer/plan/planmain.c              \
                 src/backend/optimizer/util/Makefile                \
                 src/backend/optimizer/util/clauses.c
    rm -rf src/backend/optimizer/util/constrexcl.c                  \
           src/include/optimizer/constrexcl.h
    git apply ../../patches/ConstraintExclusionSetup.patch
else
    # Hope sources have not changed (can not `git checkout` changed files)
    cd postgresql
    rm -rf src/backend/optimizer/util/constrexcl.c                  \
        src/include/optimizer/constrexcl.h
    patch -p1 < ../../patches/ConstraintExclusionSetup.patch
fi
cd ..

# Configure repository
if [ ! -f "postgresql/config.status" ] || [ "$FORCE_MODE" ]; then
    echo "Running setup script"
    (
        cd postgresql
        ./dev/setup.sh --configure-args="--without-icu --without-zstd --without-zlib --disable-tap-tests"
    )
else
    echo "Seems that repository already configured - config.status file exists"
    echo "Skipping setup script"
fi

# Setup VS Code
if code --version >/dev/null 2>&1; then
    echo "VS Code detected"
    echo "Copying VS Code configuration files into postgresql/dev"
    cp -r .vscode postgresql/.vscode
    echo "Installing extension 'C/C++'"
    code --install-extension ms-vscode.cpptools 2>/dev/null || true
    echo "Installing extension 'PostgreSQL Hacker Helper'"
    code --install-extension ash-blade.postgresql-hacker-helper 2>/dev/null || true
fi

echo "--------------------"
echo "Setting up completed"
echo ""
echo "Development scripts located under 'postgresql/dev' folder"
echo "For more info run each of them with '-h' or '--help' flags"
echo "Example: ./dev/build.sh --help"
