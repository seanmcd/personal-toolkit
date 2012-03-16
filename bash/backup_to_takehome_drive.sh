#!/bin/bash

# A script that takes the most recent system backups and copies them to a given
# backup drive, if that backup drive is present. This is designed to let my
# boss plug in an external drive in the morning and take it home in the evening
# with a backup on it, without having to do anything more. The script looks for
# an attached drive with a given UUID, and if it's present, rsyncs a backup to
# it.  This script is attuned to our particular set of backup data, and the
# special-case if blocks reflect that. This script also assumes that it's being
# run as a user that can mount filesystems on USB devices - this requires some
# fiddling with umount/automound/etc-fstab, which can be tedious to set up.

# This is the main thing you'll need to change if you start using a different
# backup drive.
TARGET_UUID="REDACTED_GUID"

# This is the filesystem location that we're going to use when we have to mount
# the takehome drive ourselves.
TARGET_MOUNT_POINT="/media/TakeHomeBackup"

# A function to make debugging the script easier and avoid infinite
# commented-out "echo $whatever" lines.
# TODO: Maybe I should figure out a way to fake something like Python's
# "include foo" for this since I use it that often.
DEBUGMODE="$1"
dbg () {
    if [[ "$DEBUGMODE" == "debug" ]]
    then
	echo "$1"
    fi
}

# This is the function we use to find and marshal the most recent copies of
# various backup data that will need to be copied to the backup drive.
copy_recent_backups () {
    FAILED_COPIES=''

    # You can tell I come from Python-ville because setting up functions like
    # this was my first thought, and I was briefly grumpy that I couldn't use a
    # closure for this.
    copy_most_recent () {
	NAME_PATTERN="$1"
	PATH_AFTER_COMMON="$2"
	cd "/media/mirrordrive/${PATH_AFTER_COMMON}"
	dbg "Searching for $NAME_PATTERN"
	MOST_RECENT=`ls -t | egrep "$NAME_PATTERN" | head -n 1`
	dbg "Found $MOST_RECENT ..."
	# Assumes that the most recent file changes between backups, which
	# seems pretty safe since the anticipated use case is that this script
	# fires every few weeks.
        cp -n "$MOST_RECENT" "$MOUNT_POINT"
	COPY_STATUS="$?"
	if [[ "$COPY_STATUS" != 0 ]]
	then
	    logger -p user.info -t backup "Failed to copy $MOST_RECENT to the external drive."
	    if [[ -n "$FAILED_COPIES" ]]
	    then
		FAILED_COPIES="$MOST_RECENT"
	    else
		FAILED_COPIES="$FAILED_COPIES and $MOST_RECENT"
	    fi
	    return 1
	else
	    return 0
	fi
    }

    # Massive block of constants for the various kinds of backups that we
    # need. I want to rewrite this in python just so I can say "for item in
    # [tuple, tuple, tuple] copy_most_recent(item)".
    QBW_NAME_PATTERN='qb_companyfile_'
    QBW_PATH_AFTER_COMMON='financials/'
    copy_most_recent "$QBW_NAME_PATTERN" "$QBW_PATH_AFTER_COMMON"

    QBB_NAME_PATTERN='qb_qbbfile_'
    QBB_PATH_AFTER_COMMON='financials/'
    copy_most_recent "$QBB_NAME_PATTERN" "$QBB_PATH_AFTER_COMMON"

    QWK_NAME_PATTERN='qw_qwfolder_'
    QWK_PATH_AFTER_COMMON='financials/'
    copy_most_recent "$QWK_NAME_PATTERN" "$QWK_PATH_AFTER_COMMON"

    W2K8_NAME_PATTERN='_Win2k8_Recovery.ova'
    W2K8_PATH_AFTER_COMMON='Win2k8_Recovery/'
    copy_most_recent "$W2K8_NAME_PATTERN" "$W2K8_PATH_AFTER_COMMON"

    WIN7_NAME_PATTERN='_Win7_Accounting.ova'
    WIN7_PATH_AFTER_COMMON='Win7_Accounting/'
    copy_most_recent "$WIN7_NAME_PATTERN" "$WIN7_PATH_AFTER_COMMON"
}


# Note that most of the time, the drive isn't mounted (it's supposed to spend
# most of its time not attached to this computer!), so this if loop will do
# nothing. That's fine.
if [[ `ls -alh /dev/disk/by-uuid/ | grep --only-matching "$TARGET_UUID"` == "$TARGET_UUID" ]]
then
    dbg "We found a disk with UUID $TARGET_UUID ..."
    DEVICE_ID=`readlink /dev/disk/by-uuid/${TARGET_UUID} | perl -pe 's/[.\/]+\/(.*)/\1/;'`
    # So far I've found that every time I reach the point of needing `sed`, I'm
    # better served by Perl. I should probably put some time into working with
    # actual Perl.
    dbg "Drive identifier appears to be $DEVICE_ID ..."
    MOUNT_POINT=`mount -l | grep "$DEVICE_ID" | perl -pe "s|/dev/$DEVICE_ID on (/.+) type ext4 .+|\1|;"`
    if [ ! -d "$MOUNT_POINT" ]
    then
	dbg "Invalid mount point. Attempting to mount drive."
	mount -t ext4 --options rw,nosuid,nodev "/dev/${DEVICE_ID}" "$TARGET_MOUNT_POINT"
	MOUNT_RESULT="$?"
	if [[ "$MOUNT_RESULT" != 0 ]]
	then
	    echo "Takehome drive is present, but couldn't be mounted."
	    exit 1
	else
	    MOUNT_POINT="$TARGET_MOUNT_POINT"
	fi
    fi
    dbg "Mount point appears to be $MOUNT_POINT ..."

    # This if-block exists because the backup tends to take an hour, and the
    # drive is used for nothing else. Therefore if a file exists on it that's
    # been modified recently, it means that a backup is in progress. If the
    # assumptions hold, this is easier than trying doing a lockfile in
    # bash. 300 minutes is long enough for the backup to finish - after that,
    # the next guard block should take care of matters by ensuring that we only
    # succeed at one backup per day. The drive isn't supposed to stay around
    # for longer than that - it's an off-site backup.
    if [[ -n "`find $MOUNT_POINT -mmin -300 -type f`" ]]
    then
	dbg "It looks like there's a backup in progress."
	exit 0
    fi

    if [[ `cat "${MOUNT_POINT}/last_backup_date.txt"` == `date +'%D'` ]]
    then
	dbg "We already made a backup to this drive today."
	exit 0
    else
	copy_recent_backups
	date +'%D' > "${MOUNT_POINT}/last_backup_date.txt"
	dbg "Updated control file to `cat ${MOUNT_POINT}/last_backup_date.txt`"
	umount "$MOUNT_POINT"
	if [[ -n "$FAILED_COPIES" ]]
	then
	    logger -p user.info -t backup "Successfully backed up to the take-home drive."
	    exit 0
	else
	    logger -p user.info -t backup "Some data failed to copy while backing up to the take-home drive."
	    logger -p user.info -t backup "What failed: $FAILED_COPIES "
	    exit 1
	fi
    fi
else
    dbg "Our drive is not present."
    # Exit with a zero code because we expect this to happen 99%+ of the times
    # the script runs.
    exit 0
fi
