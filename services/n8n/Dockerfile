ARG N8N_VERSION=latest
FROM n8nio/runners:${N8N_VERSION}

USER root

# Install additional javascript dependencies
RUN cd /opt/runners/task-runner-javascript && pnpm add cheerio
# Install additional python dependencies
RUN cd /opt/runners/task-runner-python && uv pip install numpy pandas requests beautifulsoup4

USER runner
