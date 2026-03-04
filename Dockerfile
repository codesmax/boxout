FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# Core utilities + build essentials for native npm/python packages
# Docker CLI only (no daemon — we talk to the socket proxy)
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    git \
    jq \
    unzip \
    xz-utils \
    build-essential \
    ca-certificates \
    libssl-dev \
    libffi-dev \
    ripgrep \
    docker.io \
    docker-compose \
    # Python (for projects that need it at the system level, mise handles versioned installs)
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Sandbox user — UID/GID 1000 matches the default on most Linux desktops.
# On macOS, Docker Desktop maps container UIDs to the host user transparently.
RUN groupadd -g 1000 sandbox \
    && useradd -m -u 1000 -g 1000 -s /bin/bash sandbox \
    && usermod -aG docker sandbox

# mise binary installed system-wide.
# Build-time tools go to /opt/mise-seed (owned by sandbox) so USER sandbox can
# write there during the image build. The home volume is mounted at /home/sandbox
# at runtime, which would hide anything installed there; /opt/mise-seed is outside
# the home dir so it stays accessible. The entrypoint seeds MISE_DATA_DIR from
# /opt/mise-seed on first run so tools are immediately available without a fresh
# download, and any subsequently installed tools persist in the home volume.
ENV MISE_DATA_DIR=/opt/mise-seed
ENV MISE_CONFIG_DIR=/etc/mise
RUN curl https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise bash \
    && echo 'eval "$(mise activate bash)"' >> /etc/bash.bashrc \
    && mkdir -p /opt/mise-seed /etc/mise \
    && chown sandbox:sandbox /opt/mise-seed /etc/mise

# Install tools as sandbox so all tool files are owned correctly from the start
USER sandbox
RUN mise use --global node@lts && mise install

# Other AI agent CLIs
# Claude Code is installed at runtime by entrypoint.sh into the persistent home
# volume so that auto-updates survive container restarts.
RUN mise exec -- npm install -g @openai/codex

# Back to root for system file installation
USER root

# At runtime, MISE_DATA_DIR lives in the home volume so tool installs persist
# across container restarts and project-specific versions are cached.
ENV MISE_DATA_DIR=/home/sandbox/.local/share/mise

# Entrypoint handles runtime home-volume initialisation (skills, plugins, MCP config)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Bundled Claude Code hooks (installed into the home volume by entrypoint.sh)
COPY hooks/ /usr/local/lib/claude-hooks/
RUN chmod +x /usr/local/lib/claude-hooks/*.sh

ENV PATH="/home/sandbox/.local/share/mise/shims:$PATH"

USER sandbox
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
