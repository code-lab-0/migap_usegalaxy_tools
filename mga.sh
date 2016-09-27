#!/bin/bash
INPUT=$1
OUTPUT=$2
OPTION=${@:3}

CONTAINER_ID=`cat /proc/1/cpuset`
CONTAINER_ID="${CONTAINER_ID##*/}"

IMG="yookuda/mga"

/bin/docker run \
    --volumes-from $CONTAINER_ID \
    $IMG \
        mga $INPUT $OPTION > $OUTPUT \
