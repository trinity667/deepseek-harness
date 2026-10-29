# syntax=docker/dockerfile:1.7
# DeepSeek Harness web server image (amd64 or arm64). Build context: the
# repository root — `docker compose -f deploy/oracle/compose.yml build`.

ARG NODE_IMAGE=node:24.22.1-bookworm-slim

FROM ${NODE_IMAGE} AS build
WORKDIR /app

# Native modules compile with node-gyp; git is read by build scripts.
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# CI=true skips the lefthook installer; the image never needs the Electron
# desktop binary or Playwright browsers.
ENV CI=true \
    ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    NODE_OPTIONS=--max-old-space-size=6144

# .git is not in the build context; the client bundle stamps this hash.
ARG DSH_CLIENT_COMMIT_HASH=0000000
ENV DSH_CLIENT_COMMIT_HASH=${DSH_CLIENT_COMMIT_HASH}

RUN corepack enable
COPY . .
RUN pnpm install --frozen-lockfile
RUN pnpm run build

FROM ${NODE_IMAGE} AS runtime
WORKDIR /app

# Tools the agent's shell commands expect to find.
RUN apt-get update \
  && apt-get install -y --no-install-recommends git bash ca-certificates ripgrep procps curl \
  && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production \
    DSH_HOME=/data/dsh

COPY --from=build --chown=node:node /app /app
RUN mkdir -p /data/dsh /workspace && chown -R node:node /data /workspace

USER node
WORKDIR /workspace

# Listens on loopback only; cloudflared (same host network) is the way in.
ENTRYPOINT ["node", "/app/apps/cli/lib/bin.js"]
CMD ["web", "--patch", "/config/freellmapi.patch.yml", "--no-open"]
