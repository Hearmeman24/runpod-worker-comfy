# Use multi-stage build with caching optimizations
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 AS base

# Consolidated environment variables
ENV DEBIAN_FRONTEND=noninteractive \
   PIP_PREFER_BINARY=1 \
   PYTHONUNBUFFERED=1 \
   CMAKE_BUILD_PARALLEL_LEVEL=8

# Consolidated installation to reduce layers
RUN apt-get update && apt-get install -y --no-install-recommends \
   python3.10 python3-pip git wget libgl1 git-lfs libglib2.0-0 \
   python3-dev build-essential gcc \
   && ln -sf /usr/bin/python3.10 /usr/bin/python \
   && ln -sf /usr/bin/pip3 /usr/bin/pip \
   && apt-get clean \
   && rm -rf /var/lib/apt/lists/*

# Use build cache for pip installations
RUN pip install --no-cache-dir \
   comfy-cli runpod requests

# Install ComfyUI in one step
RUN /usr/bin/yes | comfy --workspace /comfyui install \
   --cuda-version 11.8 --nvidia --version 0.3.12

# Model download stage with wget optimization
FROM base AS downloader
WORKDIR /comfyui

COPY src/extra_model_paths.yaml /comfyui/extra_model_paths.yaml

WORKDIR /comfyui/models
RUN git lfs install \
   && git clone https://huggingface.co/Aitrepreneur/insightface \
   && mkdir -p /comfyui/models/pulid \
   && wget -O /comfyui/models/pulid/pulid_flux_v0.9.0.safetensors https://huggingface.co/Aitrepreneur/FLX/resolve/main/pulid_flux_v0.9.0.safetensors?download=true

# Final stage
FROM base AS final
COPY --from=downloader /comfyui/extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY --from=downloader /comfyui/models /comfyui/models
COPY src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json *snapshot*.json /
RUN pip install --no-cache-dir numpy \
   && pip install --no-cache-dir insightface==0.7.3 \
   && chmod +x /start.sh /restore_snapshot.sh \
   && /restore_snapshot.sh

CMD ["/start.sh"]