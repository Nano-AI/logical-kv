#!/bin/zsh
# Round 2 v2 tail: is masking's accuracy loss at L=8 leakage? lag_refresh (exact rollback) at L=8, then the L=1 pair.
cd "$(dirname "$0")"
while kill -0 54377 2>/dev/null; do sleep 10; done  # v2/lat8 lag_trunc finishing
run() { echo "=== $(date '+%H:%M:%S') START $*"; env "$@" || echo "=== FAILED $*"; echo "=== $(date '+%H:%M:%S') DONE $*"; }
P=".venv/bin/python run.py --n 30 --cond"
V="GUARD=1 MASK_ON=refuted"
run OUT=results/v2/lat8 LATENCY=8 ${=V} ${=P} lag_refresh
run OUT=results/v2/lat1 LATENCY=1 ${=V} ${=P} lag_mask
run OUT=results/v2/lat1 LATENCY=1 ${=V} ${=P} lag_trunc
echo "=== ALL DONE $(date '+%H:%M:%S')"
