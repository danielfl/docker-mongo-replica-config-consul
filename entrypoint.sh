#!/bin/bash

if [ -z $RUN_WAIT_TIME ]; then
    NEXTRUN_WAIT_TIME=3
fi
if [ -z $CONSUL_SERVICE_NAME ]; then
    CONSUL_SERVICE_NAME=mongo
fi

if [ ! -z $1 ]; then
    exec "$@"
else
    while true; do
        /rs-config.sh
        if [ $? -ne 0 ]; then
            sleep 1
        else
            sleep $NEXTRUN_WAIT_TIME
        fi
    done
fi
