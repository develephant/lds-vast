#!/bin/bash
# LoRA Dataset Studio service — same contract as the image's other programs:
# wait on /.provisioning, log to stdout, supervisord owns respawn policy.
#
# The inner while-loop is the app's own restart contract (exit 75 = "restart
# requested" from Update & restart / plugin installs; other exits back off
# 10s). supervisord's autorestart stays as the outer safety net.

utils=/opt/supervisor-scripts/utils
. "${utils}/logging.sh"
. "${utils}/cleanup_generic.sh"
. "${utils}/environment.sh"

while [ -f "/.provisioning" ]; do
    echo "$PROC_NAME startup paused until instance provisioning has completed (/.provisioning present)"
    sleep 5
done

LDS_HOME="${LDS_HOME:-/opt/lds}"
DATA_DIR="${LDS_DATA_DIR:-/workspace/lds-data}"
mkdir -p "${DATA_DIR}"

# Fill never-set config values (ComfyUI :18188, /workspace/ComfyUI, Ollama
# :11434 via the user's reverse tunnel). Only empty fields are written, so
# anything the user sets in Settings survives the next boot.
/usr/bin/python3 /opt/lds-seed/seed_config.py \
    || echo "[lds] config seed failed — set ComfyUI paths in Settings > Local tools"

# Dashboard tile: best-effort /etc/portal.yaml append (the file is generated
# from PORTAL_CONFIG at init, so the reliable path is adding
# localhost:5050:5050:/:LDS to the template env — this only covers forgetfulness).
/usr/bin/python3 - <<'PYEOF' || echo "[lds] WARNING: could not update /etc/portal.yaml"
import os
import yaml

path = "/etc/portal.yaml"
data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
apps = data.setdefault("applications", {})
if "LDS" not in apps:
    apps["LDS"] = {
        "hostname": "localhost",
        "external_port": 5050,
        "internal_port": 5050,
        "open_path": "/",
        "name": "LDS",
    }
    with open(path, "w", encoding="utf-8") as handle:
        yaml.dump(data, handle, default_flow_style=False, sort_keys=False)
PYEOF

cd "${LDS_HOME}"
while true; do
    env -u VIRTUAL_ENV -u PYTHONPATH -u PYTHONHOME \
        "${LDS_HOME}/.venv/bin/python" "${LDS_HOME}/backend/run.py"
    status=$?
    if [ "$status" -eq 75 ]; then
        echo "[lds] restart requested — restarting immediately"
        continue
    fi
    echo "[lds] exited ${status} — restarting in 10s"
    sleep 10
done
