#!/bin/bash

# A script that backs up the two Windows VMs on our office server. Run this
# script as the same user that owns the VMs - if you try to do it by sudo'ing
# to that user (e.g. `sudo -u vbox this_script.sh`), problems are likely to
# occur. That approach worked badly in testing. Since this script uses the
# naive backup method of taking down the VMs, exporting them as OVA apps, and
# starting them again, it will take a long time to run: set it to run in the
# middle of the night via cron.

# TODO: Make the name of the user who owns the VMs into a global variable up
# here so that that's trivially changeable. Right now, we might run into a
# false positive if we used a naive search-and-replace to change the user,
# because the user is named "vbox" and we use the `vboxmanage` program to
# control VMs.

DEBUGMODE="$1"
dbg () {
    # Just a quick thing so we don't leave commented-out echo statements all
    # over the file.
    if [[ "$DEBUGMODE" == "debug" ]]
    then
	echo "$1"
    fi
    return 0
}

# Use `vboxmanage list vms` to find the proper names of new VMs if you want to
# add them here.
TARGET_VMS="Win7_Accounting
Win2k8_Recovery"

for CURRENT_VM in $TARGET_VMS
do
    logger -p user.info -t backup "Starting a backup of the $CURRENT_VM virtual machine..."

    # Make sure the VM is in a state where it can be backed up.
    RUN_STATUS=` vboxmanage list runningvms | grep ${CURRENT_VM}`
    dbg "Matched running VM: $RUN_STATUS"
    if [[ -n "$RUN_STATUS" ]]
    then
	logger -p user.warn -t backup "${CURRENT_VM} is still running, so it couldn't be backed up. A screenshot of its current status has been captured."
	vboxmanage controlvm "$CURRENT_VM" screenshotpng "/home/vbox/Desktop/screenshots/`date +%b_%d_%Y`_${CURRENT_VM}.png"
	BACKUP_STATUS="Failed to back up $CURRENT_VM because it's still running. A screenshot was taken - consult that to see what the VM was doing when we tried to back it up."
	continue
    fi

    # Looking before we leap.
    BACKUP_DIR="/media/mirrordrive/${CURRENT_VM}"
    if [[ ! -d "$BACKUP_DIR" ]]
    then
	dbg "Backup directory: $BACKUP_DIR"
	logger -p user.warn -t backup "The directory we were going to back up $CURRENT_VM to isn't there."
	BACKUP_STATUS="Couldn't back up $CURRENT_VM because the directory for the backups is gone."
	continue
    fi

    # Actually backing up.
    vboxmanage export "$CURRENT_VM" --output "${BACKUP_DIR}/`date +%b_%d_%Y`_${CURRENT_VM}.ova"
    EXPORT_STATUS="$?"
    if [[ "$EXPORT_STATUS" != "0" ]]
    then
	logger -p user.warn -t backup "The export of $CURRENT_VM failed."
	BACKUP_STATUS="Failed to back up $CURRENT_VM because we couldn't export it to OVA."
	continue
    else
	logger -p user.info -t backup "Finished a backup of the $CURRENT_VM virtual machine."
    fi
    dbg "Starting the VM back up."
    # VM needs to be started again whether or not backup succeeded. This could
    # possibly be replaced with an invocation of the start_vm.sh script, but
    # that's too much indirection for right now.
    vboxmanage startvm "$CURRENT_VM" --type headless
done

if [[ -n "$BACKUP_STATUS" ]]
then
    exit 0
else
    logger -p user.warn -t backup "There was a problem during the backup process."
    logger -p user.warm -t backup "Problem description: $BACKUP_STATUS"
    exit 1
fi
