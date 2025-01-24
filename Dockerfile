# Stage 1: Base image with common dependencies
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 as base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1 
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git, and other necessary tools in one RUN command to reduce layers
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3-pip \
    git \
    wget \
    libgl1 \
    git-lfs \
    libglib2.0-0 \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*  # Clean up unnecessary files

# Install comfy-cli and other python packages in a single RUN step
RUN pip install comfy-cli runpod requests

# Install ComfyUI
RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 11.8 --nvidia --version 0.3.12

# Stage 2: Model downloading
FROM base as downloader

WORKDIR /comfyui
RUN mkdir -p models/pulid
WORKDIR /comfyui/models/pulid

# Download models and the PuLID model
RUN git lfs install \
    && git clone https://huggingface.co/Aitrepreneur/insightface \
    && wget -O pulid_flux_v0.9.0.safetensors https://huggingface.co/Aitrepreneur/FLX/resolve/main/pulid_flux_v0.9.0.safetensors?download=true

# Stage 3: Final image with models
FROM base as final

# Install specific version of insightface
RUN pip install insightface==0.7.3

# Copy models and configurations from downloader stage to the final image
COPY --from=downloader /comfyui/models /comfyui/models

# Add scripts and files
COPY src/extra_model_paths.yaml src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh /restore_snapshot.sh

# Optionally copy snapshot files
COPY *snapshot*.json /

# Restore snapshot and install custom nodes
RUN /restore_snapshot.sh

# Start container
CMD ["/start.sh"]
