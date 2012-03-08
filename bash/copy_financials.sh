#!/bin/bash

# A short script to zip and copy the financial programs' files (QuickBooks and
# QuoteWerks) from the shared folder on the Windows box where they live to the
# backup area on the server that this script runs on. This script assumes that
# the /media/mirrordrive/financials directory exists. This script can be run as
# any user that can write to /media/mirrordrive/financials - it accesses files
# on the Windows machine through SMB, and the credentials are hardcoded in this
# script.

# Global values that the whole script needs.
WIN2K8IP="REDACTED_IP"
export TMPDIR='/tmp'
MOUNTPOINT=`mktemp -d`
BKP_AREA=`mktemp -d`
BKP_TARGET='/media/mirrordrive/financials'

# Global values we need for backing up QuickBooks
QBW_SOUGHT_EXTENSION="qbw"
QBW_PATH_AFTER_MOUNT="QB file"
QBW_BKP_NAME_FORMULA="qb_companyfile_`date '+%b-%d-%Y'`.zip"

# Global values we need for backing up QuickBooks QBB files
QBB_SOUGHT_EXTENSION="qbb"
QBB_PATH_AFTER_MOUNT="QB file/Backups"
QBB_BKP_NAME_FORMULA="qb_qbbfile_`date '+%b-%d-%Y'`.zip"

# Global values we need for backing up QuoteWerks
QWK_SOUGHT_EXTENSION="quotewerks"
QWK_PATH_AFTER_MOUNT="QuoteWerks/"
QWK_BKP_NAME_FORMULA="qw_qwfolder_`date '+%b-%d-%Y'`.zip"

# A function to make debugging the script easier and avoid infinite
# commented-out "echo $whatever" lines.
DEBUGMODE="$1"
dbg () {
    if [[ "$DEBUGMODE" == "debug" ]]
    then
	echo "$1"
    fi
    return 0
}

# The skeleton shared between making backups of different things.
backup_task () {
    # Expects a three-letter file extension as $1, a relative path as $2, and a
    # way to name the backup zip file as $3.
    SOUGHT_EXTENSION="$1"
    PATH_AFTER_MOUNT="$2"
    BKP_NAME_FORMULA="$3"
    dbg "Looking for ${SOUGHT_EXTENSION} files in ${MOUNTPOINT}/${PATH_AFTER_MOUNT}"
    cd "${MOUNTPOINT}/${PATH_AFTER_MOUNT}"

    # When backing up the QuickBooks files we need a specific file.
    if [[ "$SOUGHT_EXTENSION" == "qbw" || "$SOUGHT_EXTENSION" == "qbb" ]]
    then
	# Assumes that the QBW and QBB files will not be in the same directory,
	# and that the correct file to back up is the one that's been modified
	# most recently.
	CURRENTLY_BACKING_UP=`ls -tr . | egrep -i '.qb[wb]$' | tail -n 1`
    fi

    # When backing up the QuoteWorks files we need a whole folder.
    if [[ "$SOUGHT_EXTENSION" == "quotewerks" ]]
    then
	CURRENTLY_BACKING_UP="${MOUNTPOINT}/${PATH_AFTER_MOUNT}"
    fi

    if [[ -n "$CURRENTLY_BACKING_UP" ]]
    then
	dbg "Backing up ${CURRENTLY_BACKING_UP}."
    else
	echo "Not backing up a valid file or folder, bailing out."
	return 2
    fi

    # Making sure that this command is only in one place to avoid possible
    # future problems. DRY is a healthy habit.
    tar_command () {
	VERBOSE_TAR=`dbg "-v"`
	TAR_EXCLUSIONS="--exclude='[tT]humbs.db' --exclude='bluehost_order_htmls' --exclude-vcs --exclude-backups"
	dbg "Using tar in verbose mode: $VERBOSE_TAR"
	tar "$VERBOSE_TAR" "$TAR_EXCLUSIONS" -cz -f "${BKP_AREA}/${BKP_NAME_FORMULA}" "$CURRENTLY_BACKING_UP"
	TAR_STATUS="$?"
    }

    # If we're backing up either of the QuickBooks files, do the IFS black magic.
    if [[ "$SOUGHT_EXTENSION" == "qbw" || "$SOUGHT_EXTENSION" == "qbb" ]]
    then
        # "IFS" is the bash shell's "Internal Field Separator": see
	# http://stackoverflow.com/a/1574921/244494 for more.  This string of
	# commands briefly rearranges bash's guts, runs our command, then puts
	# bash back the way it was. We have to do this fiddling because the
	# full path to the QuickBooks files on Windows, contains a space
	# (i.e. ASCII 0x20), which can't be escaped because of how bash
	# interprets arguments, expansion, and escaping.
	dbg "Applying IFS black magic:"
	SPACE_IFS=$IFS
	IFS='\n'
	tar_command
	dbg "Peeling off IFS black magic."
	IFS=$SPACE_IFS
    else
	tar_command
    fi

    # Account for the fact that `tar` might not succeed (e.g. file in use)
    if [[ "$TAR_STATUS" != 0 ]]
    then
	echo "Exit status of tar: $TAR_STATUS"
	if [[ "$TAR_STATUS" == 1 ]]
	then
	    echo "Some files changed on disk while tar was running."
	    # Note: the man page tells us that "if tar was given '--create,
            # '--append' or '--update' option, this exit code means that some
            # files were changed while being archived and so the resulting
            # archive does not contain the exact copy of the file set." So
            # we're willing to treat this exit code as a success because we're
            # creating a series of archives and are scheduling this script to
            # run at times when we expect to normally not encounter this error.
	else
            # This branch is for when tar tells us that stuff just didn't work.
	    echo "Couldn't create a $CURRENTLY_BACKING_UP archive (${BKP_NAME_FORMULA}). Waiting 5s, then unmounting."
	    sleep 5
	    return 1
	fi
    fi

    # Check that the backup landed where we want it to. Probably redudant,
    # could be removed in future.
    dbg "Looking for the backup in $BKP_AREA ..."
    FILE_IN_TMP=`find "$BKP_AREA" -iname "$BKP_NAME_FORMULA" -mtime 0`
    dbg "Sending the backup to its new home in $BKP_TARGET"
    cd "$BKP_AREA"
    FILE_IN_BKP=`find . -iname "$BKP_NAME_FORMULA" -mtime 0 | xargs -I % mv -u --target-directory="${BKP_TARGET}" %`
    # If we really wanted to be paranoid, we'd have an if-block here that
    # looked like `if [[ -n "$FILE_IN_TMP" && -n "$FILE_IN_BKP" ]] - but that's
    # an enhancement for later since it covers a failure case we're not really
    # worried about right now.
}

# Starting the main action: Mount the shared folder on the Windows 2008 machine.
smbmount '\\'${WIN2K8IP}'\Users\Administrator\Documents' "$MOUNTPOINT" -o user=redacted_user,password=redacted_password
MOUNT_AVAILABLE="$?"
if [[ "$MOUNT_AVAILABLE" != 0 ]]
then
    echo "Couldn't mount the Windows share, have to bail out."
    exit 3
fi

backup_task "$QBB_SOUGHT_EXTENSION" "$QBB_PATH_AFTER_MOUNT" "$QBB_BKP_NAME_FORMULA"
backup_task "$QBW_SOUGHT_EXTENSION" "$QBW_PATH_AFTER_MOUNT" "$QBW_BKP_NAME_FORMULA"
backup_task "$QWK_SOUGHT_EXTENSION" "$QWK_PATH_AFTER_MOUNT" "$QWK_BKP_NAME_FORMULA"

# Cleanup stage.
dbg "Doing cleanup ..."

# Don't bother courting bugs by deleting the $MOUNTPOINT folder - we shouldn't
# have left anything in there, and if we did, the sytem will clean it up later
# without our having to worry about.
dbg "Unmounting $MOUNTPOINT ..."

umount "$MOUNTPOINT"
UNMOUNTED="$?"
MOUNTS_IN_TMP=`mount -l | grep '/tmp/tmp'`
if [[ "$UNMOUNTED" != 0 || -n "$MOUNTS_IN_TMP" ]]
then
    echo "Potential problem: something is still mounted in /tmp."
    echo "$MOUNTS_IN_TMP"
    # Trying to umount something that we didn't mount explicitly in this script
    # would probably cause exciting and unforeseeable results. So we'll just
    # warn about it.
else
    dbg "Unmounted successfully."
fi

exit 0
