#!/bin/bash

# A script that uses rsync to back up either the production or the development
# environment from the appropriate server, depending on command-line
# argument. Expects one command line argument, which should be either
# 'production' or 'development'. Additional words will be ignored, non-matching
# words will cause the script to politely quit. Writes results to system
# logs. Sends backups to a folder on the vbox user's desktop for now. This
# script assumes that the user running it has an SSH key that allows
# no-password login to the servers in question, which should be set up via
# ~/.ssh/config
# Intended use: run nightly via cron.

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/bin"
# The $PATH extension was necessary to get the right rsync, but it was extended
# by just copy-pasting my $path, so it probably doesn't need the whole thing.

TARGET=$1

SERVER_BACKUP_FOLDER='/home/username/BACKUPS'
BACKUP_OWNER="localuser"

if [[ "$TARGET" != "production" ]] && [[ "$TARGET" != "development" ]]
then
    echo "Please use either 'development' or 'production' as the argument."
    exit 1
fi

if [[ "$TARGET" == "production" ]]
then
    SERVER='127.0.0.1'
    DESTINATION='/media/mirrordrive/production'
else
    # Shortcut here since we know from the first if-block that if it's not
    # production then it must be development.
    SERVER='127.0.0.1'
    DESTINATION='/media/mirrordrive/development'
fi

logger -p user.info -t backup "Beginning a scheduled backup for ${TARGET}."

# Find the most recent backup zip file.
ZIPFILE=`ssh -q "${SERVER}" "ls -tr ${SERVER_BACKUP_FOLDER} | grep zip | tail -n 1"`
#echo "exit status was $?"
logger -p user.info -t backup "Found ${ZIPFILE} on ${TARGET} (${SERVER})"

# Copy it to the local archive.
rsync -az -vv "${SERVER}:${SERVER_BACKUP_FOLDER}/${ZIPFILE}" "${DESTINATION}/${ZIPFILE}"
logger -p user.info -t backup "The rsync backup finished with status ${?}"

chown "$BACKUP_OWNER":"$BACKUP_OWNER" "${DESTINATION}/${ZIPFILE}"
logger -p user.info -t backup "Changed ownership of the ${ZIPFILE} backup to user ${BACKUP_OWNER}."
