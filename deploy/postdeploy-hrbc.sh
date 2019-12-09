#!/bin/bash

: ${TIMEOUT_HRBC:=120}

status=""
for s in $(seq 0 5 $TIMEOUT_HRBC); do
    echo -n "@${s}s: "
    if [ -n "$(docker logs ${NAME//[-_]/}_db01_1 2>/dev/null| grep -oe 'MySQL init process done.')" ]; then
        status="ok"
        echo "success."
        break;
    else
        echo "fail"
    fi
        
    sleep 5;
done

if [ -n $status ]; then
    echo "Deploy finished"
else
    echo "Deploy Failed"
    exit 1;
fi