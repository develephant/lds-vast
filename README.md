# lds-vast — LoRA Dataset Studio inside vast.ai's ComfyUI image

`FROM vastai/comfy:v0.43.0` + LDS cloned, venv'd (managed CPython 3.12 via uv),
and registered as a supervisord service beside the image's own ComfyUI.

```
+-------------------- vast.ai instance --------------------+
|  supervisord                                             |
|   ├─ comfyui        127.0.0.1:18188  (image's own)        |
|   └─ lds            127.0.0.1:5050   (this image)         |
|         base_dir = /workspace/ComfyUI  (native!)          |
|         data     = /workspace/lds-data                    |
|  portal/caddy: external :5050 -> internal :5050           |
+----------------------------------------------------------+
        |  ssh -R 11434  |                | WinSCP sync
        v                |                v
   home Ollama           |          local copy of datasets
  (ROCm, qwen3-vl)       |          (/workspace/lds-data)
```

## Build & push

```bash
cd lds-vast
docker build -t <your-repo>/lds-comfy:latest .
docker push <your-repo>/lds-comfy:latest
```

Pin a different LDS revision with `--build-arg LDS_REF=<tag-or-sha>`.

## Template env (vast.ai console)

Reuse your existing "ComfyUI LDS" template and only change the **image** to
`<your-repo>/lds-comfy:latest`, then in the env/port block:

- Ports: add `-p 5050:5050`
- `PORTAL_CONFIG`: append `|localhost:5050:5050:/:LDS`
- Keep `PROVISIONING_SCRIPT` pointing at your model manifest
  (`flux2-klein.yaml` — weights are intentionally NOT in the image)
- `HF_TOKEN` as before

Boot → Instance Portal → **LDS** tile opens the app (behind the portal token,
same as ComfyUI). Fallback: `ssh -p <port> root@<host> -L 5050:127.0.0.1:5050`.

## What's wired automatically

First boot seeds `config.json` (empty fields only — user edits always win):

| key | value | why |
|---|---|---|
| `comfyui.api_url` | `http://127.0.0.1:18188` | image's internal ComfyUI |
| `comfyui.base_dir` | `/workspace/ComfyUI` | the manifest's model tree — no mount, no SSHFS |
| `ollama.url` | `http://127.0.0.1:11434` | reachable when the reverse tunnel is up |

Klein-9B generation works out of the box once the manifest drops
`flux-2-klein-9b` + `qwen_3_8b` + `flux2-vae` + `loras/klein/…consistency-V2`.

## Ollama (stays on your home box)

From the local machine, alongside your usual SSH:

```bash
ssh -R 11434:127.0.0.1:11434 -p <ssh-port> root@<instance-host>
```

Caption passes run your ROCm Ollama — free, and it doesn't fight Klein-9B
for the 32 GB of VRAM. Without the tunnel, Setup just shows Ollama
unreachable; everything else still works.

## Data & secrets

- `/workspace/lds-data` — datasets, captions, checkpoints, config. Survives
  stop/start; wiped on destroy. Point the WinSCP keep-up-to-date job at it.
- API keys (`VAST_API_KEY` for the training cloud lane, Gemini/OpenAI keys,
  `HF_TOKEN` for LDS's own model downloads): `ssh` in and write
  `/opt/lds/.env`, or set them in Settings inside the app. Never bake secrets
  into the image.
- In-app "Update & restart" works — `/opt/lds` is a full git clone and the
  exit-75 restart contract is handled by the service script.

## Notes learned the hard way

- `LDS_RUNTIME=docker-gpu` is deliberately **not** set: that mode hardcodes
  the ComfyUI readiness probe to `:8188`, and vastai/comfy serves on `:18188`.
  We run in the app's "native" posture; config drives everything.
- `LDS_HOST=127.0.0.1` on purpose: a LAN bind would make LDS demand its own
  access token *in front of* the portal's token. Loopback stays token-free.
- After LDS installs bundled ComfyUI node packs via Setup, bounce ComfyUI:
  `supervisorctl restart comfyui`.
- Requirements-ml is used as pip **constraints** only — `-r` would drag
  torch-CUDA (~7 GB) into the app venv; those packages belong in the
  runtime-created scoped envs under `data/envs`.
