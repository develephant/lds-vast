# LoRA Dataset Studio baked into vast.ai's ComfyUI image.
#
#   docker build -t <repo>/lds-comfy:latest .
#   docker push  <repo>/lds-comfy:latest
#
# Then point a vast.ai template at <repo>/lds-comfy:latest — see README.md for
# the port, PORTAL_CONFIG and provisioning env vars.
#
# Deliberately NOT baked: model weights (~27 GB, provisioned at boot by the
# template's PROVISIONING_SCRIPT) and secrets (.env / API keys — set at runtime).

# Real Docker Hub tags are vX.Y.Z-cuda-A.B-py312 ("vastai/comfy:v0.43.0" only
# resolves inside vast's template UI). cuda-12.9 is what ran on the RTX 5090;
# v0.43.0-cuda-13.2-py312 is the alternative for newer-driver hosts.
ARG BASE_IMAGE=vastai/comfy:v0.43.0-cuda-12.9-py312
FROM ${BASE_IMAGE}

ARG LDS_REF=v2
ARG LDS_REPO=https://github.com/perfectgf/lora-dataset-studio.git
ARG LDS_HOME=/opt/lds

# uv brings a managed CPython 3.12: LDS's ML extras (insightface/numpy<2) only
# publish wheels through 3.12, and the base image's own python is not a
# version contract we control.
COPY --from=ghcr.io/astral-sh/uv:0.9.0 /uv /uvx /usr/local/bin/

# Full clone (not --depth 1): the in-app "Update & restart" does git pull.
# ML extras go into the app venv with requirements-ml.txt as CONSTRAINTS —
# the file also pins torch-pulling packages that belong in the runtime-created
# scoped envs under data/envs, so it is a constraint source, not a -r input.
RUN set -eux; \
    git clone --branch "${LDS_REF}" "${LDS_REPO}" "${LDS_HOME}"; \
    uv python install 3.12; \
    uv venv --python 3.12 "${LDS_HOME}/.venv"; \
    uv pip install --python "${LDS_HOME}/.venv/bin/python" \
        -r "${LDS_HOME}/backend/requirements.txt"; \
    uv pip install --python "${LDS_HOME}/.venv/bin/python" \
        insightface onnxruntime rembg rapidocr-onnxruntime \
        opencv-python-headless \
        -c "${LDS_HOME}/backend/requirements-ml.txt"

# Native-runtime posture (no LDS_RUNTIME/LDS_DOCKER_*): the image's docker
# modes hardcode ComfyUI's readiness probe to :8188, but vastai/comfy serves
# ComfyUI on :18188 — so we look like a plain co-located install and let
# config.json drive api_url/base_dir/ollama.url (see seed_config.py).
#
# 127.0.0.1 bind, not 0.0.0.0: the portal proxies localhost, and a LAN bind
# would trip netguard's access-token requirement in front of the portal's
# own token gate.
ENV LDS_HOST=127.0.0.1 \
    LDS_PORT=5050 \
    LDS_DATA_DIR=/workspace/lds-data \
    LDS_CONFIG=/workspace/lds-data/config.json \
    LDS_BIND_MANAGED=1 \
    LDS_AUTO_PORT=0 \
    LDS_RESTART_MODE=supervisor

COPY files/opt/supervisor-scripts/lds.sh /opt/supervisor-scripts/lds.sh
COPY files/etc/supervisor/conf.d/lds.conf /etc/supervisor/conf.d/lds.conf
COPY files/opt/lds-seed/seed_config.py /opt/lds-seed/seed_config.py
RUN chmod +x /opt/supervisor-scripts/lds.sh
