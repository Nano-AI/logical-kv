"""Poll the Colab VM's logs; print run start/done/failure, errors, a status line every 10 problems,
spend, stalls, and ALL DONE. usage: python watch_cloud.py <l4 start epoch> <units/h> [log ...]"""
import os
import re
import subprocess
import sys
import time

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T0, RATE = float(sys.argv[1]), float(sys.argv[2])
LOGS = sys.argv[3:] or ["run.log"]
env = dict(os.environ, HOME=f"{PROJ}/.colab-home",
           GOOGLE_APPLICATION_CREDENTIALS=os.path.expanduser("~/.config/gcloud/application_default_credentials.json"))
os.makedirs(f"{PROJ}/results_cloud", exist_ok=True)
# RESUME=1: start after the lines already in the local copies (reported before a re-arm)
seen = {g: sum(1 for _ in open(f"{PROJ}/results_cloud/{g}", errors="ignore"))
        if os.environ.get("RESUME") and os.path.exists(f"{PROJ}/results_cloud/{g}") else 0 for g in LOGS}
size = {g: -1 for g in LOGS}
ok = {g: time.time() for g in LOGS}
warned = {g: 0.0 for g in LOGS}
last_change, done = time.time(), False


def say(msg):
    print(msg, flush=True)


def alert(msg):
    """QUIET=1 (background job): exit on anything that needs a human, so the one exit notification is the alert"""
    say(msg)
    if os.environ.get("QUIET"):
        sys.exit(2)


loop = 0
while not done:
    spend = (time.time() - T0) / 3600 * RATE
    # check in with the VM every loop (Colab reclaimed the last one ~1 h after its client went quiet),
    # and refresh the local result snapshot every ~10 min
    for cmd, every in (("beat", 1), ("pull", 5)):
        if loop % every:
            continue
        try:
            r = subprocess.run([f"{PROJ}/cloud/colab.sh", cmd], cwd=PROJ, capture_output=True, text=True, timeout=300)
            out = (r.stderr + r.stdout)[-300:]
            # only beat can tell: pull's res.tgz is legitimately "not found" before the first 5-min snapshot
            if cmd == "beat" and ("not found" in out.lower() or "no active sessions" in out.lower()):
                alert(f"VM GONE ({cmd}): {out.strip()[-160:]} | spend~{spend:.1f}u")
        except subprocess.TimeoutExpired:
            pass
    loop += 1
    for log in LOGS:
        local = f"{PROJ}/results_cloud/{log}"
        try:
            r = subprocess.run(["colab", "--auth=adc", "download", "-s", "lkv",
                                f"/content/lkv/{log}", local], env=env, capture_output=True, text=True, timeout=90)
            out = (r.stderr + r.stdout).strip()
            err = (r.returncode or "failed" in out.lower()) and out[-160:]
        except subprocess.TimeoutExpired:
            err = "timed out"
        if err:
            if time.time() - ok[log] > 600 and time.time() - warned[log] > 600:
                say(f"WARN {log}: no successful fetch for {(time.time() - ok[log]) / 60:.0f} min ({err})")
                warned[log] = time.time()
            continue
        ok[log] = time.time()
        lines = open(local, errors="ignore").read().splitlines()
        if len(lines) != size[log]:
            size[log], last_change = len(lines), time.time()
        n = c = 0
        w, total = 0.0, 100
        for i, line in enumerate(lines):
            if line.startswith("=== "):
                n = c = 0
                w = 0.0
                total = int((re.search(r"--n (\d+)", line) or [0, total])[1])
            elif line.startswith("["):
                n += 1
                m = re.search(r"gold=([ABC]) pred=([ABC]?)", line)
                c += bool(m and m.group(1) == m.group(2))
                w += float(re.search(r"wall=([0-9.]+)", line).group(1))
            if i < seen[log]:
                continue
            if re.search(r"Traceback|Error|FAILED|Killed|CUDA", line):
                alert(f"{line[:200]} | spend~{spend:.1f}u")
            elif line.startswith("=== "):
                say(f"{line.replace('.venv/bin/python run.py ', '')[:200]} | spend~{spend:.1f}u")
            elif line.startswith("[") and n % 10 == 0:
                say(f"{line.split()[0]} {n}/{total} acc={100 * c / n:.1f}% mean_wall={w / n:.1f}s | spend~{spend:.1f}u")
        seen[log] = len(lines)
        # DONES=n: exit after the n-th queue finishes (queues can be chained in one run.log)
        done |= log == "run.log" and sum(l.startswith("=== ALL DONE") for l in lines) >= int(os.environ.get("DONES", 1))
    if time.time() - last_change > 900:
        alert(f"STALL: no new log lines for {(time.time() - last_change) / 60:.0f} min | spend~{spend:.1f}u")
        last_change = time.time()
    if spend > 100:
        alert("ALERT: estimated spend passed 100 units")
    if not done:
        time.sleep(120)
# all queues done: take the final snapshot and release the VM so it stops billing
r = subprocess.run([f"{PROJ}/cloud/colab.sh", "pull"], cwd=PROJ, capture_output=True, text=True, timeout=600)
say(f"ALL DONE. pull: {(r.stdout + r.stderr).strip()[-200:]}")
r = subprocess.run([f"{PROJ}/cloud/colab.sh", "down"], cwd=PROJ, capture_output=True, text=True, timeout=300)
say(f"VM released: {(r.stdout + r.stderr).strip()[-200:]}")
