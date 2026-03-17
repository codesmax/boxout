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

  # ─── Claude settings: sync permissions from repo ─────────────────────────────
  # Overwrites only the permissions block so other user settings (hooks, plugins,
  # etc.) are preserved. Runs on every start so permissions stay in sync with the
  # committed config without requiring a full rebuild.
  _src="/etc/claude/settings.json"
  _target="$HOME/.claude/settings.json"
  if [[ -f "$_src" ]]; then
    if [[ -f "$_target" ]]; then
      _tmp=$(mktemp)
      jq --argjson perms "$(jq '.permissions' "$_src")" '.permissions = $perms' "$_target" > "$_tmp" \
        && mv "$_tmp" "$_target"
    else
      cp "$_src" "$_target"
    fi
  fi
  unset _src _target _tmp

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
    ln -sf "$HOME/.claude/anthropic-skills/skills" "$HOME/.claude/skills"
  fi
fi

exec "$@"
