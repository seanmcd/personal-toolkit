#!/bin/bash

# This script creates and maintains a reverse tunnel from the office server to
# a remote server so the remote server can reach machines only reachable from
# the office server. This is prone to creating security problems when done
# poorly, so one should, at a minimum, use SSH keys and passphrases for login,
# use an SSH key pair not used elsewhere, and use non-privileged accounts that
# can only log in via SSH with their key pairs, not with passwords..

# Run this script as a cron job: it is minimally useful if it's only run once -
# the feature that one really wants is that it re-establishes the connection if
# it's lost or if it sees an external prompt to do so.

# A function to make debugging the script easier and avoid infinite
# commented-out "echo $whatever" lines.
DEBUGMODE="$1"
dbg () {
    if [[ "$DEBUGMODE" == "debug" ]]
    then
	echo "$1"
    fi
}

# Connection information. Since we're just passing this along to SSH,
# $DEFAULT_ENDPOINT can be either an IP address or a DNS name - both are fine.
DEFAULT_ENDPOINT="127.0.0.1"
DEFAULT_LOGIN="tunnel_user"
DEFAULT_RSA_ID="${HOME}/.ssh/tunnel_id_rsa"
DEFAULT_PORT="22"
DEFAULT_TUNNEL_PORT="2695"

# If you're okay with having the connection information located outside this
# file, just put this block in the `~/.ssh/config` file of the user that runs
# the script:
#     Host tunnel-server
#     User tunnel_user
#     IdentityFile ~/.ssh/tunnel_id_rsa
#     HostName 127.0.0.1
#     Port 22
# With that block present, you can use a much shorter SSH invocation, e.g.
#     `ssh -fnNT -R 2695:localhost:22 tunnel-server`
# in the create_tunnel() function.

# A remote URL that the script will look at to determine whether it should
# re-establish the tunnel.
REMOTE_CONTROL_URL="http://example.org/my-tunnel.txt"

# If $OVERRIDE_ENDPOINT is set to a non-null value, the script will look at the
# first line of the content of $REMOTE_CONTROL_URL and try to use that as an
# endpoint of the tunnel instead of the default endpoint.
OVERRIDE_ENDPOINT=""

# Setup and teardown.
create_tunnel () {
    if [[ -n "$NEW_ENDPOINT" ]]
    then
	CHOSEN_ENDPOINT="$NEW_ENDPOINT"
    else
	CHOSEN_ENDPOINT="$DEFAULT_ENDPOINT"
    fi
    # This usually breaks if there is no identity file: this is by design.
    dbg "Creating a tunnel to $CHOSEN_ENDPOINT ..."
    TUNNEL_CREATED=$(ssh -fnNT -R "${DEFAULT_TUNNEL_PORT}:localhost:22" -i "$DEFAULT_RSA_ID" -p "$DEFAULT_PORT" -l "$DEFAULT_LOGIN" -o "ExitOnForwardFailure yes" -o "ControlMaster no" "$CHOSEN_ENDPOINT" 2>&1)
    dbg "SSH output: ${TUNNEL_CREATED}"
}

kill_tunnel () {
    PSRESULTS=`ps aux | egrep "[s]s[h] .fnNT -R .* $DEFAULT_LOGIN"`
    dbg "SSH process: $PSRESULTS"
    # Breaks if this runs as a user whose login name has [^a-z] in it. May also
    # fail if there's more than one process that matches the $PSRESULTS regex.
    SSH_PID=`echo "$PSRESULTS" | awk '{print $2}'`
    if [[ -n "$SSH_PID" ]]
    then
	echo "$SSH_PID" | while read CURRENT_PID; do
	    dbg "Trying to kill: $CURRENT_PID ..."
	    kill "$CURRENT_PID"
	done
    else
	dbg "No matching SSH process to kill."
    fi
}

# Functions that tell us whether or not we need to create the connection again.
local_heartbeat () {
    HEARTBEAT=`ps aux | egrep "[s]s[h].*$DEFAULT_ENDPOINT"`
    dbg "Local status was: $HEARTBEAT"
    if [[ -z "$HEARTBEAT" ]]
    then
	# If there's no local ssh process running, that's bad.
	LOCAL_STATUS='DOWN'
    else
	LOCAL_STATUS='OK'
    fi
    echo "$LOCAL_STATUS"
}

remote_heartbeat () {
    if [[ -z "OVERRIDE_ENDPOINT" ]]
    then
	VERBOSITY='--head'
    else
	VERBOSITY='--verbose'
    fi

    HEARTBEAT=$(curl -Ss "$VERBOSITY" "$REMOTE_CONTROL_URL" 2>&1)
    dbg "Full reply was: $HEARTBEAT"
    HTTP_REPLY=`echo $HEARTBEAT | egrep --only-matching 'HTTP/1.1 200 OK'`
    dbg "HTTP status was: $HTTP_REPLY"
    if [[ -n "$HTTP_REPLY" ]]
    then
	# If the server returned HTTP 200, things are fine on that end.
	REMOTE_STATUS='OK'
    else
	# If the server returned anything other than "things are fine," we
	# interpret that as a request to set up the tunnel again. If the
	# server's busy, it might have dropped the connection: try again. If
	# the file isn't there (HTTP 404) that's our sign to try again. If we
	# can't reach the network and don't know what the server's status is,
	# that means we've already lost our connection and should try to
	# re-establish.
	REMOTE_STATUS='DOWN'
    fi

    if [[ -z "OVERRIDE_ENDPOINT" ]]
    then
	NEW_ENDPOINT=`echo $HEARTBEAT | egrep -v '^[<>\*{] ?' | egrep '[a-z0-9.\-]+[.][a-z]{2,4}|[0-9.]{8,32}'`
    else
	NEW_ENDPOINT=''
    fi

    echo "$REMOTE_STATUS"
}


# Decide whether or not to create a tunnel.
main () {
    CURRENT_STATUS=`remote_heartbeat`
    dbg "Remote status: $CURRENT_STATUS"
    if [[ "$CURRENT_STATUS" == "OK" || `dbg "OK"` == "OK" ]]
    then
	dbg "The server did not ask for a new connection."
	CURRENT_STATUS=`local_heartbeat`
	dbg "Local status: $CURRENT_STATUS"
	if [[ "$CURRENT_STATUS" == "OK" || `dbg "OK"` == "OK" ]]
	then
	    dbg "We have a tunnel - things are okay."
	    dbg "Current tunnel: `ps aux | egrep 'ssh -fnNT -[R]'`"
	    exit 0
	else
	    dbg "We don't have a tunnel, so we're going to start one."
	    kill_tunnel
	    create_tunnel
	fi
    else
	dbg "Based on server status, we need to restart the tunnel."
	kill_tunnel
	create_tunnel
    fi
}

# We've wound everything up - now, go!
main
