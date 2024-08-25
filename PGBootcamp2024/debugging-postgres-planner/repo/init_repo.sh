#!/usr/bin/bash

# Clone repository
git clone https://git.postgresql.org/git/postgresql.git \
    --single-branch --branch=REL_16_4 postgresql

# Setup dev scripts
mkdir -p postgresql/dev
cp utils.sh setup.sh build.sh run.sh clean.sh   \
    get_current_backend_pid.sh test.sh          \
    postgresql/dev
chmod +x postgresql/dev/*

# Setup VS Code config files
mkdir -p postgresql/.vscode
cp *.json postgresql/.vscode
