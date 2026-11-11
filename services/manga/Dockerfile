# syntax=docker/dockerfile:1
FROM python:3.13-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install CPU-only torch first, otherwise mokuro pulls the CUDA build (~3 GB of nvidia wheels)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu

ARG MOKURO_VERSION=latest
RUN --mount=type=cache,target=/root/.cache/pip \
    if [ "$MOKURO_VERSION" = "latest" ]; then \
    pip install mokuro; \
    else \
    pip install mokuro==${MOKURO_VERSION}; \
    fi

RUN groupadd -g 1000 mokuro && \
    useradd -u 1000 -g 1000 -m -s /bin/bash mokuro

USER mokuro

WORKDIR /data/downloads/media/books/Manga

CMD ["tail", "-f", "/dev/null"]
