#!/bin/bash
INPUT1=$1
shift
INPUT2=$1
shift
INPUT3=$1
shift
OUTPUT1=$1
shift

CONTAINER_ID=`cat /proc/1/cpuset`
CONTAINER_ID="${CONTAINER_ID##*/}"

IMG="yookuda/fa4tr"

/bin/docker run \
    --volumes-from $CONTAINER_ID \
    --rm \
    $IMG \
    perl /scripts/fa4tr.pl \
        --fa $INPUT1 \
        --cog $INPUT2 \
        --ref $INPUT3 \
        --out $OUTPUT1

