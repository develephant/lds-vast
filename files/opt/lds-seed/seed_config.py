#!/usr/bin/env python3
"""Seed container-owned config values for LDS on the vastai/comfy image.

Runs before every LDS start (from /opt/supervisor-scripts/lds.sh) and writes
ONLY missing/empty fields, atomically — nothing a user set in Settings is
ever overwritten. Modeled on upstream packaging/docker/seed_comfy_config.py.

Seeded values:
  comfyui.api_url   http://127.0.0.1:18188  image's internal ComfyUI
  comfyui.base_dir  /workspace/ComfyUI      provisioning manifest's model tree
  ollama.url        http://127.0.0.1:11434  home Ollama via `ssh -R` tunnel
"""

import json
import os
import sys
from pathlib import Path

CONFIG = Path(os.environ.get("LDS_CONFIG", "/workspace/lds-data/config.json"))
COMFY_BASE = "/workspace/ComfyUI"

DEFAULTS = {
    "comfyui": {"api_url": "http://127.0.0.1:18188"},
    "ollama": {"url": "http://127.0.0.1:11434"},
}
# Only promise the install dir once the provisioning manifest has actually
# dropped a model tree; a later boot heals it if this one ran too early.
if Path(COMFY_BASE, "models").is_dir():
    DEFAULTS["comfyui"]["base_dir"] = COMFY_BASE


def main() -> int:
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    try:
        current = json.loads(CONFIG.read_text("utf-8")) if CONFIG.exists() else {}
    except json.JSONDecodeError:
        print(f"[lds-seed] {CONFIG} is not valid JSON — leaving untouched",
              file=sys.stderr)
        return 0
    if not isinstance(current, dict):
        return 0

    filled = []
    for section, values in DEFAULTS.items():
        node = current.setdefault(section, {})
        if not isinstance(node, dict):
            continue
        for key, value in values.items():
            existing = node.get(key)
            if existing is None or (isinstance(existing, str) and not existing.strip()):
                node[key] = value
                filled.append(f"{section}.{key}")

    if filled:
        tmp = CONFIG.with_suffix(".tmp")
        tmp.write_text(json.dumps(current, indent=2) + "\n", "utf-8")
        os.replace(tmp, CONFIG)

    print(f"[lds-seed] {'filled ' + ', '.join(filled) if filled else 'nothing to do'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
