# Export the necessary environment variables to use ESP-IDF.

addIdfEnvVars() {
    # Crude way to detect if $1 is the ESP-IDF derivation.
    if [ -e "$1/tools/idf.py" ]; then
        export IDF_PATH="$1"
        export IDF_TOOLS_PATH="$IDF_PATH/tools"
        export IDF_PYTHON_CHECK_CONSTRAINTS=no
        export IDF_PYTHON_ENV_PATH="$(readlink $IDF_PATH/python-env)"
        # ESP-IDF's own activation (tools/activate.py) exports this; the
        # idf-component-manager 3.x reads it (without the 'v' prefix) and
        # crashes on idf.py startup when it is unset.
        export ESP_IDF_VERSION="$(sed -n 's/^v//p' "$1/version.txt")"
        addToSearchPath PATH "$IDF_TOOLS_PATH"

        # Extra paths from `export.sh` in the ESP-IDF repo.
        addToSearchPath PATH "${IDF_PATH}/components/espcoredump"
        addToSearchPath PATH "${IDF_PATH}/components/partition_table"
        addToSearchPath PATH "${IDF_PATH}/components/app_update"

        [ -e "$1/.tool-env" ] && . "$1/.tool-env"

        # use a derivation-specific system-level git config if specified
        if [ -e "$1/etc/gitconfig" ]; then
            export GIT_CONFIG_SYSTEM="$1/etc/gitconfig"
        fi
    fi
}

addEnvHooks "$hostOffset" addIdfEnvVars
