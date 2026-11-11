#!/bin/bash
MAC=10.0.200.5
loop() { while true; do socat PTY,link=$1,raw,echo=0 TCP:$MAC:$2,nodelay; sleep 0.5; done; }
loop /tmp/m1n1 4000 &
loop /tmp/m1n1-console 4001 &
wait
