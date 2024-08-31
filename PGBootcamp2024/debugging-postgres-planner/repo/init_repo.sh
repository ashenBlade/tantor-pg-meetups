#!/usr/bin/bash



# Clone repository
git clone https://git.postgresql.org/git/postgresql.git \
    --single-branch --branch=REL_16_4 postgresql

# Setup dev scripts
cp -r dev postgresql/dev

# Setup VS Code config files
cp -r .vscode postgresql/.vscode

# Install required extensions
code --install-extension ash-blade.postgresql-hacker-helper
code --install-extension ms-vscode.cpptools
