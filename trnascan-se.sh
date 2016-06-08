#!/bin/bash
INPUT=$1
OUTPUT=$2
OPTION=${@:3}

CONTAINER_ID=`cat /proc/1/cpuset`
CONTAINER_ID="${CONTAINER_ID##*/}"

IMG="yookuda/trnascan_se"

/bin/docker run \
    --volumes-from $CONTAINER_ID \
    --rm \
    $IMG \
        tRNAscan-SE \
            $OPTION \
            -Q \
            -f $OUTPUT $INPUT \
            > ${OUTPUT}.out \
            2> ${OUTPUT}.err

