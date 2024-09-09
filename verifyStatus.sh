#!/bin/bash

# Param :
SRC_CLUSTER="mongodb+srv://meir:mig123@cluster0.kaffo.mongodb.net/"
DST_CLUSTER="mongodb+srv://meir:mig123@cluster1.kaffo.mongodb.net/"
MIN_TIME_LAST_WRITE_IN_SEC=120
IPMONGOSYNC=localhost:27182


EXIT_ON_ERROR="false"

# ip:port
# mongosync

let "o=0"
let "n=0"

# script

RPL_JS="rplInfo=db.getReplicationInfo();rplInfo['tLastTmstp']=Date.parse(rplInfo['tLast'])/1000;rplInfo['nowTmstp']=Date.parse(rplInfo['now'])/1000;rplInfo['writeAgoSec']=rplInfo['nowTmstp']-rplInfo['tLastTmstp'];JSON.stringify(rplInfo)"

echo "----------------------------------------------"
echo "| verify migration cutoff commit prerequisite "
echo "| SRC : $SRC_CLUSTER"
echo "| DST : $DST_CLUSTER"
echo "----------------------------------------------"


progressResult=$(curl $IPMONGOSYNC/api/v1/progress -XGET)
#progressResult='{"progress":{"state":"RUNNING","canCommit":true,"canWrite":false,"info":"change event application","lagTimeSeconds":0,"collectionCopy":{"estimatedTotalBytes":694,"estimatedCopiedBytes":694}},"success": true}'
progressCanCommit=$(echo $progressResult|jq -r '.progress.canCommit')
lag=$(echo $progressResult|jq -r '.progress.lagTimeSeconds')

echo "progressCanCommit=$progressCanCommit;lag=$lag"

if [ "$progressCanCommit" == "true" ]; then
  echo "[OK] Can commit is true"
  let "o++"
else
  echo "[NOK] Can commit is not true"
  let "n++"
fi


if [ $lag -lt 10 ]; then
  echo "[OK] lag $lag is less than 10s"
  let "o++"
else
  echo "[NOK] lag $lag is NOT less than 10s"
  let "n++"
fi



LAST_OP='db.getSiblingDB("local").oplog.rs.find().sort({$natural:-1}).limit(1)'

echo "----------------------------------------------"
echo "| verify for no write "
echo "----------------------------------------------"

SRC_RPL=$(mongosh "$SRC_CLUSTER" --eval "$RPL_JS")
DST_RPL=$(mongosh "$DST_CLUSTER" --eval "$RPL_JS")

echo "SRC_RPL : $SRC_RPL"
echo "DST_RPL : $DST_RPL"

lastSrc="$(echo $SRC_RPL|jq '.tLast')"
writeAgoTimeSrc="$(echo $SRC_RPL|jq '.writeAgoSec')"

lastDst="$(echo $DST_RPL|jq '.tLast')"
writeAgoTimeDst="$(echo $DST_RPL|jq '.writeAgoSec')"

echo "-----------------------------------------------"
echo " SRC : $lastSrc     ($writeAgoTimeSrc)"
echo " SRC : $lastDst     ($writeAgoTimeDst)"
echo "-----------------------------------------------"
stat="ok"

if [ "$MIN_TIME_LAST_WRITE_IN_SEC" -gt "$writeAgoTimeSrc" ]; then
    echo "write on src only $writeAgoTimeSrc minimum should be $MIN_TIME_LAST_WRITE_IN_SEC"
    LST=$(mongosh "$SRC_CLUSTER" --eval "$LAST_OP")
    echo "Last source op : $LST"
    if [ "$EXIT_ON_ERROR" == "true" ]; then
      exit 1
    fi
    stat="nok"
fi

if [ "$MIN_TIME_LAST_WRITE_IN_SEC" -gt "$writeAgoTimeDst" ]; then
    echo "write on dst only $writeAgoTimeDst minimum should be $MIN_TIME_LAST_WRITE_IN_SEC"
    LST=$(mongosh "$DST_CLUSTER" --eval "$LAST_OP")
    echo "Last Dest op : $LST"
    if [ "$EXIT_ON_ERROR" == "true" ]; then
          exit 1
    fi
    stat="nok"
fi

if [ "$stat" == "ok" ]; then
  let "o++"
  echo "Write ok : no more write"
else
  let "n++"
  echo "Write nok : still write"
fi

SRC_COUNT=$(mongosh "$SRC_CLUSTER" -f collectionCountAndIndex.js)
echo "SRC_COUNT=$SRC_COUNT"
echo $SRC_COUNT > src.json
DST_COUNT=$(mongosh "$DST_CLUSTER" -f collectionCountAndIndex.js)
echo "DST_COUNT=$DST_COUNT"
echo $DST_COUNT > dst.json

EQUAL=$(jq --argfile a src.json --argfile b dst.json -n 'def post_recurse(f): def r: (f | select(. != null) | r), .; r; def post_recurse: post_recurse(.[]?); ($a | (post_recurse | arrays) |= sort) as $a | ($b | (post_recurse | arrays) |= sort) as $b | $a == $b')
echo "EQUAL=$EQUAL"
if [ "$EQUAL" = "false" ]; then
  echo "count are different check it using countDocuments"
  diff \
    <(jq -S 'def post_recurse(f): def r: (f | select(. != null) | r), .; r; def post_recurse: post_recurse(.[]?); (. | (post_recurse | arrays) |= sort)' "src.json") \
    <(jq -S 'def post_recurse(f): def r: (f | select(. != null) | r), .; r; def post_recurse: post_recurse(.[]?); (. | (post_recurse | arrays) |= sort)' "dst.json")

  listOfCol=$(jq -n 'input as $src | input as $dst | reduce ($src|keys_unsorted[]) as $k ({keys:[]}; if ($dst | has($k) and $src[$k] != $dst[$k]) or ( $dst | true != has($k)) then .keys+=[$k] else . end) ' src.json dst.json | jq -rc .keys[])
  echo "list of collections with different statistics : $listOfCol"
  while IFS= read -r line || [[ -n $line ]]; do
      IFS=. read database collection <<<"${line##*-}"
      cmd="db.getSiblingDB('$database').getCollection('$collection').countDocuments( {}, { hint: \"_id_\"} )"
      echo "executing on both : $cmd"

      srcCount=$(mongosh "$SRC_CLUSTER" --eval "$cmd")
      dstCount=$(mongosh "$DST_CLUSTER" --eval "$cmd")
      if [ $srcCount -eq $dstCount ]; then
         echo "[OK] false difference on the stats $line is the same on source $srcCount and dest $dstCount"
         let "o++"
      else
         echo "[NOK] real difference on the stats $line is the same on source $srcCount and dest $dstCount"
         let "n++"
      fi
  done < <(printf '%s' "$listOfCol")
  exit 1
else
  let "o++"
fi

echo "-----------------------------------------------"
echo "sample comparison"
echo "-----------------------------------------------"
mongosh "$SRC_CLUSTER" -f sampleHash.js > src.json

while read -r line
do
  echo "$line" > cur.js
  res=$(mongosh "$DST_CLUSTER" -f cur.js -f verifyHash.js)
  echo $res
  stat=$(echo $res|jq -r ".[].status" )
  echo "$stat"
  if [ "$stat" == "ok" ]; then
     let "o++"
  else
     let "n++"
  fi
done < "src.json"


echo "Results : OK=$o NOK=$n"

