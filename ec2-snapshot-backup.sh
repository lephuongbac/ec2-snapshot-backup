#!/bin/bash -l
#
# This script backups EC2 snapshots from tag name
# Created By:         Oluwaseun Obajobi
# Created Date:       September 25, 2013
# Last Modified Date: September 25, 2013
#
# -t web -n 2 -cr ap-southeast-1 -dr eu-west-1 -b sunday -dn 3

TAGPREFIX=""
CREGION="ap-southeast-1"
DREGION="eu-west-1"
NUMBER="0"
DNUMBER="0"
DATE=`date +%Y-%m-%dT%H.%M.%SZ`
DAY=`date +%a`


printhelp() {

echo "

Usage: ec2-snapshot-backup [OPTION]...
  -t,    --tagprefix   The AWS Tag Name, Default is Empty

  -n,    --number      The maximum number of snapshots to be left
               
  -dn,   --dnumber     The maximum number of snapshots to be left at the DR

  -cr,   --cregion     The current region to backup the EBS volume, Default is ${CREGION}

  -dr,   --dregion     The destination region to backup the EBS volume, Default is to ${DREGION}

  -b,    --backup-day  The day of the week to backup the EBS volume to DR region.
		       
  -h,    --help        Display help file

"

}

[ "$1" == "" ] && printhelp && exit;

while [ "$1" != "" ]; do
  case "$1" in
    -t    | --tagprefix )          TAGPREFIX=$2; shift 2 ;;
    -n    | --number )             NUMBER=$2; shift 2 ;;
    -dn   | --dnumber )            DNUMBER=$2; shift 2 ;;
    -cr   | --cregion )            CREGION=$2; shift 2 ;;
    -dr   | --dregion )            DREGION=$2; shift 2 ;;
    -b    | --backup-day )         BKPDAY=$2; shift 2 ;;
    -h    | --help )	           echo "$(printhelp)"; exit; shift; break ;;
  esac
done

BKPDAY=$(tr '[a-z]' '[A-Z]' <<< ${BKPDAY:0:1})${BKPDAY:1}
BACKUPDAY=$( echo "$BKPDAY" |cut -c -3)
LOGFILE=/var/log/ec2-snapshot-backup.log
AWAKEY='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
AWSKEY='BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'

let NUMBER--
if [ -z "$DNUMBER" ]; then
  let DNUMBER--
fi

$EC2_HOME/bin/ec2-describe-volumes --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
              --filter "tag:Name=${TAGPREFIX}*" | grep VOLUME | cut -f2 > /tmp/ec2-snapshot-${TAGPREFIX}-tag-list

VOLUMES=(`cat /tmp/ec2-snapshot-${TAGPREFIX}-tag-list`)

# Loop the Instance IDs
for VOLUME in `cat /tmp/ec2-snapshot-${TAGPREFIX}-tag-list | sed ':a;N;$!ba;s/\n/ /g'`
do
  echo $VOLUME
  TAGNAME=(`$EC2_HOME/bin/ec2-describe-volumes --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
              $VOLUME | grep TAG | grep Name | cut -f5`)
  echo $TAGNAME


  # Create Snapshot Backup
  echo "" >> $LOGFILE
  echo "$(date +'%Y-%m-%d %T'): STARTING + $TAGNAME instance backup." >> $LOGFILE
  $EC2_HOME/bin/ec2-create-snapshot --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
              $VOLUME -d "Scheduled Snapshot of [${TAGNAME}] from [${VOLUME}] on [${DATE}]" > /tmp/ec2_snapshot_identity

  #Saving the Snapshot ID of the Volume backup
  VOL_SNAP_ID=`cat /tmp/ec2_snapshot_identity | cut -f2`
  $EC2_HOME/bin/ec2-create-tags --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
              ${VOL_SNAP_ID} --tag "Name=${TAGNAME}-${DATE}"
  echo -e "$(date +'%Y-%m-%d %T'): COMPLETED + $TAGNAME instance backup as $VOL_SNAP_ID." >> $LOGFILE


  # Delete OLD snapshot leaving one
  echo -e "$(date +'%Y-%m-%d %T'): CLEANUP + Checking for old $TAGNAME snapshot backup..." >> $LOGFILE
  $EC2_HOME/bin/ec2-describe-snapshots --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
               | grep TAG | grep ${TAGNAME} | grep -v ${VOL_SNAP_ID} | cut -f3 \
               > /tmp/ec2-snapshot-old-$TAGNAME-list

  FILELIST=(`cat /tmp/ec2-snapshot-old-${TAGNAME}-list`)
  FILECOUNT=`echo ${FILELIST[*]} | wc -w`

  if [ $FILECOUNT -gt $NUMBER ]
  then
    echo "$(date +'%Y-%m-%d %T'): CLEANUP + Old snapshot found, removing ${FILELIST[0]} from set..." >> $LOGFILE
    $EC2_HOME/bin/ec2-delete-snapshot --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION ${FILELIST[0]}
    echo "$(date +'%Y-%m-%d %T'): CLEANUP + Completed ${FILELIST[0]} snapshot removal." >> $LOGFILE
  else
    echo "$(date +'%Y-%m-%d %T'): CLEANUP + No available OLD $TAGNAME snapshot found." >> $LOGFILE
  fi

  # Copying the Image
  if [ -z "$BACKUPDAY" ] || [ "$BACKUPDAY" != "$DAY" ]; then
    echo "$(date +'%Y-%m-%d %T'): No need for weekly ${TAGNAME} snapshot to backup to ${DREGION} " >> $LOGFILE
  elif [ "$BACKUPDAY" == "$DAY" ]; then
    echo "$(date +'%Y-%m-%d %T'): Saving weekly ${TAGNAME} snapshot to ${DREGION} " >> $LOGFILE

    # Wait for snapshot to be available.
    REQUIRED_STATUS="completed"
    STATUS=`$EC2_HOME/bin/ec2-describe-snapshots --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
               $VOL_SNAP_ID | grep SNAPSHOT | cut -f4`
    while [ $STATUS != $REQUIRED_STATUS ]
    do
      sleep 60
      STATUS=`$EC2_HOME/bin/ec2-describe-snapshots --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$CREGION \
               $VOL_SNAP_ID | grep SNAPSHOT | cut -f4`
      echo "$(date +'%Y-%m-%d %T'): Waiting 60secs for ${TAGNAME} snapshot to be available for copy " >> $LOGFILE
    done

    $EC2_HOME/bin/ec2-copy-snapshot --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$DREGION \
               -r $CREGION -s ${VOL_SNAP_ID} -d "Scheduled Snapshot of [${TAGNAME}] from [${VOLUME}] on [${DATE}]"

    #Deleting OLD Old from the DR Region
    $EC2_HOME/bin/ec2-describe-snapshots --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$DREGION \
               | grep TAG | grep ${TAGNAME} | grep -v ${VOL_SNAP_ID} | cut -f3 \
               > /tmp/ec2-snapshot-old-$TAGNAME-list

    FILELIST=(`cat /tmp/ec2-snapshot-old-${TAGNAME}-list`)
    FILECOUNT=`echo ${FILELIST[*]} | wc -w`
    if [ $FILECOUNT -gt $DNUMBER ]
    then
      echo "$(date +'%Y-%m-%d %T'): Starting the ${FILELIST[0]} snapshot removal from set" >> $LOGFILE
      $EC2_HOME/bin/ec2-delete-snapshot --aws-access-key=$AWAKEY --aws-secret-key=$AWSKEY --region=$DREGION ${FILELIST[0]}
      echo "$(date +'%Y-%m-%d %T'): Completed removing ${FILELIST[0]} snapshot in ${CREGION}." >> $LOGFILE
    else
      echo "$(date +'%Y-%m-%d %T'): CLEANUP + No available OLD $TAGNAME snapshot found in ${DREGION}." >> $LOGFILE
    fi
    echo "$(date +'%Y-%m-%d %T'): DONE ++ Saved weekly ${TAGNAME} snapshot to ${DREGION} " >> $LOGFILE
  fi
done
