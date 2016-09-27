#!/bin/bash
INPUT=$1
OUTPUT=$2
OPTION=${@:3}

CONTAINER_ID=`cat /proc/1/cpuset`
CONTAINER_ID="${CONTAINER_ID##*/}"

IMG="yookuda/rnammer-1.2:1.0"

/bin/docker run \
    --volumes-from $CONTAINER_ID \
    $IMG \
        rnammer \
            $OPTION \
            -gff - $INPUT \
            > $OUTPUT
