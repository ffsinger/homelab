FROM python:3.13-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

ARG MOKURO_VERSION=latest
RUN if [ "$MOKURO_VERSION" = "latest" ]; then \
    pip install --no-cache-dir mokuro; \
    else \
    pip install --no-cache-dir mokuro==${MOKURO_VERSION}; \
    fi

RUN groupadd -g 1000 mokuro && \
    useradd -u 1000 -g 1000 -m -s /bin/bash mokuro

USER mokuro

WORKDIR /data/downloads/media/books/Manga

CMD ["tail", "-f", "/dev/null"]
