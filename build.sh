#!/usr/bin/env bash

VERSION_STRING=$(dapp --version | grep dapp)
oIFS=${IFS}
IFS=' '
read -a ARR <<<${VERSION_STRING}
DAPP_VERSION=${ARR[1]}
IFS='.'
read -a ARR <<<${DAPP_VERSION}
IFS=${oIFS}
MAJOR=${ARR[0]}
MINOR=${ARR[1]}
PATCH=${ARR[2]}

if [ ${MAJOR} = 0 ]; then
    if [ ${MINOR} -lt 32 ]; then
        echo "Incompatible dapp version; must use at least 0.32.2"
        exit 1
    fi
    if [ ${MINOR} = 32 ] && [ ${PATCH} -lt 2 ]; then
        echo "Incompatible dapp version; must use at least 0.32.2"
        exit 1
    fi
fi

DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.6.12 build
