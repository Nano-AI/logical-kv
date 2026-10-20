#!/bin/bash
# Runs ON the Colab VM, from /content/lkv. Driven by cloud/colab.sh on the Mac.
#   vm.sh setup Qwen3-14B [Qwen3-30B-A3B ...]   CUDA build of the same packages as the Mac, models, KV smoke test
#   vm.sh queue Qwen3-14B [n] [v3]              the v2 condition set (results/RESULTS.md, round 2) at n problems;
#                                               v3: no step cap (safety limits only), checker verifies any formula,
#                                               verdict cache, no rollback probe -> results_cloud/<model>_v3
#   vm.sh mini Qwen3-8B [n]                     L=8 only: lag_trunc, lag_mask, lag_mask+RETRY, lag_mask+INFER -> results_cloud/<model>_infer
#   vm.sh eff Qwen3-14B [n]                     L=8 only, DEPWAIT=1 LOOP=2: lag_trunc, lag_mask, lag_refresh+HYBRID=50 -> results_cloud/<model>_eff
#   vm.sh sweep Llama-3.1-8B,Phi-4,... [n]      the v2 condition set for each model in turn (names: see src())
set -euo pipefail
cd /content/lkv
export PATH=/usr/local/cuda/bin:$PATH UV_LINK_MODE=copy
gguf() { echo "models/$1-Q4_K_M.gguf"; }
src() {  # Hugging Face repo and file for a model name; Qwen's own repos follow one pattern, the rest are bartowski's quants
  case $1 in
    Llama-3.1-8B) echo bartowski/Meta-Llama-3.1-8B-Instruct-GGUF Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf ;;
    Phi-4) echo bartowski/phi-4-GGUF phi-4-Q4_K_M.gguf ;;
    Mistral-Small-24B) echo bartowski/Mistral-Small-24B-Instruct-2501-GGUF Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf ;;
    *) echo "Qwen/$1-GGUF" "$1-Q4_K_M.gguf" ;;
  esac
}

case $1 in
setup)
  shift
  command -v uv >/dev/null || pip install -q uv
  [ -x .venv/bin/python ] || uv venv -q .venv --python 3.12
  # no prebuilt CUDA wheel past 0.3.19, so build 0.3.36 (what the Mac runs) for this GPU: ~8 min on an L4.
  # ponytail: rebuilt per VM; the 140 MB wheel is over the CLI's upload limit, chunk it if VMs churn
  CMAKE_ARGS="-DGGML_CUDA=on -DCMAKE_CUDA_ARCHITECTURES=native" CMAKE_BUILD_PARALLEL_LEVEL=$(nproc) \
    uv pip install -q --python .venv/bin/python llama-cpp-python==0.3.36 z3-solver==5.3.1.0 numpy==2.5.4 huggingface-hub==2.2.0
  for m in "$@"; do
    read -r repo file < <(src "$m")
    .venv/bin/python -c "from huggingface_hub import hf_hub_download as d; d('$repo', '$file', local_dir='models')"
    [ -e "$(gguf "$m")" ] || ln -s "$file" "$(gguf "$m")"
    MODEL=$(gguf "$m") .venv/bin/python run.py --spike  # mid-cache KV removal must still work on CUDA
  done
  nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv
  ;;
queue|mini|eff)
  M=$(gguf "$2") N=${3:-100} O=results_cloud/$2
  [ "${4:-}" = v3 ] && { O=${O}_v3; export CHECK_ALL=1 CACHE=1 MAX_STEPS=60 MAX_GEN=5000 BASE_MAX=4000 PROBE=0; }
  [ "$1" = mini ] && O=${O}_infer
  [ "$1" = eff ] && O=${O}_eff
  # snapshot results every 5 min for colab.sh pull: Colab can reclaim the VM, and run.py resumes from the jsonl
  snap() { tar czf /content/res.tmp.tgz results_cloud && mv /content/res.tmp.tgz /content/res.tgz; }
  (while sleep 300; do snap; done) & SNAP=$!
  trap 'kill $SNAP; snap' EXIT
  run() { echo "=== $(date '+%H:%M:%S') START $*"; env "$@" || echo "=== FAILED $*"; echo "=== $(date '+%H:%M:%S') DONE $*"; }
  P=".venv/bin/python run.py --n $N --cond"
  V="GUARD=1 MASK_ON=refuted"
  if [ "$1" = eff ]; then  # efficiency fixes on each policy (answer waits only for its ancestors; loops cropped) + the hybrid
    E="DEPWAIT=1 LOOP=2"
    run MODEL=$M OUT=$O/lat8 LATENCY=8 $V $E $P lag_trunc
    run MODEL=$M OUT=$O/lat8 LATENCY=8 $V $E $P lag_mask
    run MODEL=$M OUT=$O/lat8 LATENCY=8 $V $E HYBRID=50 $P lag_refresh
    echo "=== ALL DONE $(date '+%H:%M:%S')"
    exit 0
  fi
  if [ "$1" = mini ]; then  # where masking failed (L=8): truncation, masking, mask + forced retry, mask + solver-inferred dependents
    run MODEL=$M OUT=$O/lat8 LATENCY=8 $V $P lag_trunc
    run MODEL=$M OUT=$O/lat8 LATENCY=8 $V $P lag_mask
    run MODEL=$M OUT=$O/lat8_retry LATENCY=8 $V RETRY=1 $P lag_mask
    run MODEL=$M OUT=$O/lat8_infer LATENCY=8 $V INFER=1 $P lag_mask
    echo "=== ALL DONE $(date '+%H:%M:%S')"
    exit 0
  fi
  run MODEL=$M OUT=$O $P base
  run MODEL=$M OUT=$O $P fmt
  run MODEL=$M OUT=$O $V $P sync
  # most informative first (free-tier sessions can end early): L=8 is where mask vs trunc differed significantly
  for L in 8 3 1; do
    run MODEL=$M OUT=$O/lat$L LATENCY=$L $V $P lag_trunc
    run MODEL=$M OUT=$O/lat$L LATENCY=$L $V $P lag_mask
    [ $L = 8 ] && run MODEL=$M OUT=$O/lat8 LATENCY=8 $V $P lag_refresh
  done
  echo "=== ALL DONE $(date '+%H:%M:%S')"
  ;;
sweep)  # vm.sh sweep M1,M2,... [n]: the queue for each model in turn (one ALL DONE per model; watcher: DONES=<count>)
  IFS=, read -ra MS <<< "$2"
  for m in "${MS[@]}"; do bash cloud/vm.sh queue "$m" "${3:-30}" || echo "=== FAILED queue $m"; done
  echo "=== SWEEP DONE $(date '+%H:%M:%S')"
  ;;
*) echo "usage: vm.sh setup MODEL... | queue MODEL [n] | sweep M1,M2,... [n]"; exit 1 ;;
esac
