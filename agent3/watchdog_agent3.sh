#!/bin/bash
LOGFILE="/root/projects/agent3/watchdog.log"

if ! systemctl is-active --quiet agent3; then
    echo "$(date) - Agent3 not running. Restarting..." >> $LOGFILE
    systemctl restart agent3
else
    echo "$(date) - Agent3 running OK" >> $LOGFILE
fi
