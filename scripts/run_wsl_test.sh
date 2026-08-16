#!/usr/bin/env bash
set -euo pipefail

cd /home/l4d2/server
exec ./srcds_run \
    -game left4dead2 \
    -console \
    -usercon \
    -nomaster \
    -tickrate 100 \
    +port 27015 \
    +map c1m1_hotel \
    +exec astmod_test.cfg
