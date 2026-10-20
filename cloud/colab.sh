#!/bin/bash
# Mac side: rent a Colab GPU and run the experiments there. One-time setup:
#   brew install --cask google-cloud-sdk && uv tool install google-colab-cli
#   gcloud auth application-default login --scopes=openid,https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/userinfo.email,https://www.googleapis.com/auth/colaboratory
# Then:
#   cloud/colab.sh up [L4]            rent the VM (bills compute units until `down`)
#   cloud/colab.sh setup MODEL...     upload code, build, download models, KV smoke test   e.g. Qwen3-14B Qwen3-30B-A3B
#   cloud/colab.sh start MODEL [n] [v3|mini|eff|sweep]  run the condition set, detached on the VM (resumes from uploaded results)
#                                     sweep: MODEL is a comma-separated list, run in turn
#   cloud/colab.sh beat               progress check-in; run every few minutes, Colab reclaims VMs nobody talks to
#   cloud/colab.sh pull               results_cloud/ (snapshot <=5 min old) + results_cloud/run.log (live)
#   cloud/colab.sh down               release the VM
#   cloud/colab.sh usage              compute-unit balance and burn rate
set -euo pipefail
cd "$(dirname "$0")/.."
# CLI state lives in the project (so it also runs inside a sandbox); auth is your gcloud ADC login
export GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS:-$HOME/.config/gcloud/application_default_credentials.json} \
  HOME=${COLAB_HOME:-$PWD/.colab-home} PATH=$HOME/.local/bin:$PATH
mkdir -p "$HOME"
C="colab --auth=adc"
S="-s ${COLAB_SESSION:-lkv}"
T=${TMPDIR:-/tmp}
remote() {  # stream the VM command's output here line by line; fail if it fails or hangs (an exec can hang for hours after a dropped websocket)
  printf '%s\n' "import subprocess, sys" "p = subprocess.Popen('''$1''', shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)" \
    "for line in p.stdout: print(line, end='', flush=True)" "sys.exit(p.wait())" | perl -e 'alarm shift; exec @ARGV' "${REMOTE_TIMEOUT:-300}" $C exec $S; }

case ${1:-} in
up) $C new $S --gpu "${2:-L4}" ;;
setup)
  shift
  tar czf "$T/lkv.tgz" run.py logic.py analyze.py data papers/proverqa_prompt.txt cloud $(ls -d results_cloud 2>/dev/null)
  $C upload $S "$T/lkv.tgz" /content/lkv.tgz
  # the build takes ~10 min and a blocking exec can drop ("Connection was lost"): detach it and poll for the marker
  remote "mkdir -p /content/lkv && tar xzf /content/lkv.tgz -C /content/lkv && (setsid nohup bash -c 'bash /content/lkv/cloud/vm.sh setup $*; echo \"=== SETUP EXIT \$?\"' > /content/lkv/setup.log 2>&1 &) && echo detached"
  until out=$(remote "tail -n 1 /content/lkv/setup.log" 2>/dev/null) && [[ $out == *"SETUP EXIT"* ]]; do sleep 60; done
  remote "tail -n 12 /content/lkv/setup.log"
  [[ $out == *"SETUP EXIT 0"* ]] ;;
start)
  q=queue; case ${4:-} in mini|eff|sweep) q=$4 ;; esac
  # the exec websocket drops now and then ("Connection was lost"): retry, and never start a second queue on the VM
  for i in 1 2 3; do
    # anchored: the launching shell's own command line also contains "bash cloud/vm.sh $q", but after "/bin/sh -c"
    out=$(REMOTE_TIMEOUT=90 remote "cd /content/lkv && { pgrep -f '^bash cloud/vm.sh $q ' >/dev/null && echo started already; } || { (setsid nohup bash cloud/vm.sh $q $2 ${3:-100} ${4:-} >> run.log 2>&1 &) && echo started; }" 2>&1) \
      && [[ $out == *started* ]] && { echo "$out" | grep started; exit 0; }
    echo "start attempt $i failed: $(echo "$out" | tail -n 1)" >&2; sleep 15
  done; exit 1 ;;
beat) remote "grep -c '^[[]' /content/lkv/run.log; tail -n 1 /content/lkv/run.log" ;;
pull)
  mkdir -p results_cloud
  $C download $S /content/res.tgz "$T/res.tgz" 2>/dev/null && tar xzf "$T/res.tgz" || echo "no snapshot yet"
  # a snapshot can catch a record mid-write: drop any unterminated last line so run.py can resume from the file
  find results_cloud -name '*.jsonl' -exec python3 -c 'import sys; p=sys.argv[1]; b=open(p,"rb").read(); open(p,"wb").write(b[:b.rfind(b"\n")+1])' {} \;
  $C download $S /content/lkv/run.log results_cloud/run.log
  grep -c "^\[" results_cloud/run.log | xargs echo "problems done:"; grep "===" results_cloud/run.log | tail -3 ;;
down) $C stop $S ;;
usage) $C usage; $C sessions ;;
*) sed -n 2,12p "$0"; exit 1 ;;
esac
