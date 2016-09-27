#!/bin/bash
INPUT=$1
OUTPUT=$2
OPTION=${@:3}

RRNA_DB_DIR=/home/okuda/data/db/rrna/20090220

CONTAINER_ID=`cat /proc/1/cpuset`
CONTAINER_ID="${CONTAINER_ID##*/}"

IMG="yookuda/blast_plus"

/bin/docker run \
    --volumes-from $CONTAINER_ID \
    -v $RRNA_DB_DIR:/db \
    $IMG \
        blastn \
            -db /db/16srna \
            -query $INPUT \
            -out $OUTPUT \
            -outfmt "0" \
            $OPTION

