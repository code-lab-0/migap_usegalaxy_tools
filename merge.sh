#!/bin/bash
INPUT1=$1
shift
INPUT2=$1
shift
INPUT3=$1
shift
INPUT4=$1
shift
INPUT5=$1
shift
OUTPUT1=$1
shift
OUTPUT2=$1
shift
OUTPUT3=$1
shift
OUTPUT4=$1
shift
OUTPUT5=$1
shift
OUTPUT6=$1
shift
OUTPUT7=$1
shift

CONTAINER_ID=`cat /proc/1/cpuset`
CONTAINER_ID="${CONTAINER_ID##*/}"

IMG="yookuda/merge"

/bin/docker run \
    --volumes-from $CONTAINER_ID \
    --rm \
    $IMG \
        perl /scripts/merge.pl \
            -f $INPUT1 \
            -m $INPUT2 \
            -t $INPUT3 \
            -r $INPUT4 \
            -b $INPUT5 \
            -p $OUTPUT1

mv ${OUTPUT1}-na.fasta $OUTPUT1
mv ${OUTPUT1}-aa.fasta $OUTPUT2
mv ${OUTPUT1}.annt $OUTPUT3
mv ${OUTPUT1}.csv $OUTPUT4
mv ${OUTPUT1}.embl $OUTPUT5
mv ${OUTPUT1}.gbk $OUTPUT6
mv ${OUTPUT1}.gff $OUTPUT7
