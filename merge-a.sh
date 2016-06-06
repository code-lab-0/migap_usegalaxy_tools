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
INPUT6=$1
shift
INPUT7=$1
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

#SCRIPTS_DIR="/home/okuda/data/scripts"
COG_DB_DIR="/home/okuda/data/db/cog/20030417"
REFSEQ_DB_DIR="/home/okuda/data/db/refseq_protein/20140911"

WHOG="whog"
MYVA="myva"

GPFF="microbial.*.protein.gpff.gz"

IMG="yookuda/merge_a"

#INPUT_FNAME1="${INPUT1##*/}"
#INPUT_FNAME2="${INPUT2##*/}"
#INPUT_FNAME3="${INPUT3##*/}"
#INPUT_FNAME4="${INPUT4##*/}"
#INPUT_FNAME5="${INPUT5##*/}"
#INPUT_FNAME6="${INPUT6##*/}"
#INPUT_FNAME7="${INPUT7##*/}"
#DATA_DIR_TMP="${INPUT1%/*}"

CONTAINER_ID=`cat /proc/1/cpuset`
CONTAINER_ID="${CONTAINER_ID##*/}"

#DATA_DIR="/tmp/files/${CONTAINER_ID}/${DATA_DIR_TMP##*/}"

#OUTPUT_FNAME1="${OUTPUT1##*/}"
#OUTPUT_FNAME2="${OUTPUT2##*/}"
#OUTPUT_FNAME3="${OUTPUT3##*/}"
#OUTPUT_FNAME4="${OUTPUT4##*/}"
#OUTPUT_FNAME5="${OUTPUT5##*/}"

cp $INPUT4 ${OUTPUT1}.gbk
cp $INPUT5 ${OUTPUT1}.embl
cp $INPUT6 ${OUTPUT1}.annt
cp $INPUT7 ${OUTPUT1}.csv

docker run \
    --volumes-from $CONTAINER_ID \
    -v $COG_DB_DIR:/cog \
    -v $REFSEQ_DB_DIR:/refseq \
    --rm \
    $IMG \
        perl /scripts/merge-a.pl \
            --cog $INPUT1 \
            --trembl $INPUT2 \
            --ref $INPUT3 \
            --whog /cog/$WHOG \
            --myva /cog/$MYVA \
            --gpff /refseq/$GPFF \
            --prefix $OUTPUT1

mv ${OUTPUT1}-a.gbk $OUTPUT1
mv ${OUTPUT1}-a.embl $OUTPUT2
mv ${OUTPUT1}-a.annt $OUTPUT3
mv ${OUTPUT1}-a.csv $OUTPUT4
mv ${OUTPUT1}-a.ddbj $OUTPUT5
