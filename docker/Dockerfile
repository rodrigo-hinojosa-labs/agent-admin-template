# syntax=docker/dockerfile:1.6
FROM alpine:3.20

ARG UID=1000
ARG GID=1000

# Runtime packages. `tini` for PID 1, `bash` for scripts, `tmux` for the
# persistent session, `nodejs`/`npm` for the claude CLI, `git` for repo ops,
# `curl` for bootstrapping, `perl` for the template engine, `yq`/`jq` for
# config, `busybox-extras` for `crond`, `gum` for the in-container wizard.
RUN apk add --no-cache \
      bash \
      tini \
      tmux \
      nodejs \
      npm \
      git \
      curl \
      perl \
      jq \
      yq \
      gettext \
      busybox-extras \
      shadow \
      su-exec \
      ca-certificates

# Install gum from the charmbracelet tap alternative: use the static binary.
ARG GUM_VERSION=0.14.5
RUN set -eux; \
    arch=$(uname -m); \
    case "$arch" in \
      x86_64) gum_arch="x86_64" ;; \
      aarch64) gum_arch="arm64" ;; \
      *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_linux_${gum_arch}.tar.gz" \
      | tar -xz -C /tmp; \
    mv "/tmp/gum_${GUM_VERSION}_linux_${gum_arch}/gum" /usr/local/bin/gum; \
    rm -rf /tmp/gum_*

# Install Claude Code CLI globally so both root (for first-run chown) and
# the `agent` user can invoke it.
RUN npm install -g @anthropic-ai/claude-code

# Create the non-root agent user matching host UID/GID.
RUN addgroup -g "$GID" agent \
 && adduser -D -u "$UID" -G agent -s /bin/bash agent

# Copy in the in-image scripts (baked at build time, read-only at runtime).
COPY entrypoint.sh /opt/agent-admin/entrypoint.sh
COPY crontab.tpl /opt/agent-admin/crontab.tpl
COPY scripts/start_services.sh /opt/agent-admin/scripts/start_services.sh
COPY scripts/wizard-container.sh /opt/agent-admin/scripts/wizard-container.sh
RUN chmod +x /opt/agent-admin/entrypoint.sh \
             /opt/agent-admin/scripts/start_services.sh \
             /opt/agent-admin/scripts/wizard-container.sh

# Workspace is bind-mounted at runtime; /home/agent is a named volume.
WORKDIR /workspace

# tini is PID 1; entrypoint.sh runs as root briefly, drops to agent.
ENTRYPOINT ["/sbin/tini", "--", "/opt/agent-admin/entrypoint.sh"]
