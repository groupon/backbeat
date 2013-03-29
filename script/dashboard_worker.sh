#!/bin/bash
set -e

pid_file=/var/groupon/backbeat/shared/pids/dashboard_worker.pid
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -f $pid_file ];then
  pid=$(<$pid_file)
  kill -USR2 $pid;
  sleep 1;
fi

$DIR/runner 'Dashboard.start'&
echo $! > $pid_file
