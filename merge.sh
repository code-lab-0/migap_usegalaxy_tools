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

#INPUT_FNAME1="${INPUT1##*/}"
#INPUT_FNAME2="${INPUT2##*/}"
#INPUT_FNAME3="${INPUT3##*/}"
#INPUT_FNAME4="${INPUT4##*/}"
#INPUT_FNAME5="${INPUT5##*/}"
#DATA_DIR_TMP="${INPUT1%/*}"

CONTAINER_ID=`cat /proc/1/cpuset`
CONTAINER_ID="${CONTAINER_ID##*/}"

#DATA_DIR="/tmp/files/${CONTAINER_ID}/${DATA_DIR_TMP##*/}"

#OUTPUT_FNAME1="${OUTPUT1##*/}"
#OUTPUT_FNAME2="${OUTPUT2##*/}"
#OUTPUT_FNAME3="${OUTPUT3##*/}"
#OUTPUT_FNAME4="${OUTPUT4##*/}"
#OUTPUT_FNAME5="${OUTPUT5##*/}"
#OUTPUT_FNAME6="${OUTPUT6##*/}"
#OUTPUT_FNAME7="${OUTPUT7##*/}"

IMG="yookuda/merge"

docker run \
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
