#!/usr/bin/bash

# Go to root of repository
# All dev scripts located in 'dev' subdirectory
cd -- "$(dirname "${BASH_SOURCE[0]:-$0}")/.."

function source_config_file {
    # CWD must be already adjusted to top level repository directory
    CONFIG_FILE="./dev/pg_dev_config.sh"
    if [[ ! -s "$CONFIG_FILE" ]]; then
        echo "ERROR: pg_dev_config.sh does not exist or empty. " \
             "Ensure you have run ./setup.sh"
        exit 1
    fi
    source "$CONFIG_FILE"
}