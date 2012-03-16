#!/bin/bash

# A simple script that iterates over a list of VMs, starting each one if it's
# not started already. This script needs to be run as the user who owns the VMs.

TARGET_VMS="Win7_Accounting
Win2k8_Recovery"

for CURRENT_VM in $TARGET_VMS
do
    RUN_STATUS=` vboxmanage list runningvms | grep "${CURRENT_VM}"`
    if [[ -z "$RUN_STATUS" ]]
    then
	vboxmanage startvm "$CURRENT_VM" --type headless
    fi
done
