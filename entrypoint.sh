#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${HOME:-}" ]]; then
  # ─── Seed mise tool cache on first run ───────────────────────────────────────
  # Build-time tools live in /opt/mise-seed in the image. On first run (or after
  # wiping the home volume) copy them into MISE_DATA_DIR so node/npm/etc. are
  # available immediately without re-downloading.
  if [[ ! -d "$HOME/.local/share/mise/installs" ]]; then
    cp -rp /opt/mise-seed/. "$HOME/.local/share/mise/"
  fi

  # ─── Claude Code native binary ───────────────────────────────────────────────
  # Installed into the persistent home volume so the binary survives container
  # restarts and auto-updates (which write back to the same path) actually stick.
  if [[ ! -x "$HOME/.local/bin/claude" ]]; then
    curl -fsSL https://claude.ai/install.sh | bash || true
  fi

  # Update PATH to include ~/.local/bin where the claude binary is installed
  export PATH="$HOME/.local/bin:$PATH"

  [[ ! -d "$HOME/.claude" ]] && mkdir -p "$HOME/.claude"

  # ─── Anthropic skills ────────────────────────────────────────────────────────
  # Clone on first start, pull on subsequent starts to keep skills up to date.
  # Symlinked to ~/.claude/skills so Claude Code picks them up automatically.
  if [[ -d "$HOME/.claude/anthropic-skills/.git" ]]; then
    git -C "$HOME/.claude/anthropic-skills" pull --ff-only --quiet || true
  else
    git clone --depth=1 --quiet \
      https://github.com/anthropics/skills.git \
      "$HOME/.claude/anthropic-skills" || true
  fi

  if [[ ! -e "$HOME/.claude/skills" && -d "$HOME/.claude/anthropic-skills/skills" ]]; then
    ln -s "$HOME/.claude/anthropic-skills/skills" "$HOME/.claude/skills"
  fi

  # ─── Claude Code hooks ───────────────────────────────────────────────────────
  # Copy bundled hooks into the persistent home volume and register them in
  # settings.json. Idempotent — safe to run on every container start.
  mkdir -p "$HOME/.claude/hooks"
  cp /usr/local/lib/claude-hooks/*.sh "$HOME/.claude/hooks/"
  chmod +x "$HOME/.claude/hooks/"*.sh

  # Merge the PostToolUse hook entry for the inplace-write fix (idempotent).
  # Preserves the original inode after Claude's atomic writes so VSCode's file
  # watcher keeps working across bind-mounted workspaces.
  # See: https://github.com/anthropics/claude-code/issues/25438
  SETTINGS="$HOME/.claude/settings.json"
  [[ ! -f "$SETTINGS" ]] && echo '{}' > "$SETTINGS"
  TMP_SETTINGS=$(mktemp)
  jq '
    .hooks.PostToolUse //= [] |
    if any(.hooks.PostToolUse[]; .matcher == "Write|Edit") | not then
      .hooks.PostToolUse += [{
        "matcher": "Write|Edit",
        "hooks": [{"type": "command", "command": "~/.claude/hooks/inplace-write.sh"}]
      }]
    else . end
  ' "$SETTINGS" > "$TMP_SETTINGS" && mv "$TMP_SETTINGS" "$SETTINGS"
fi

exec "$@"
