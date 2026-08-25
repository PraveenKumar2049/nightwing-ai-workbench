#!/usr/bin/env bash
# Nightwing — single-command launcher.
#
# 1. Checks/starts the local Ollama server (never pulls models — this is an
#    air-gapped deployment; models must already be present from setup time).
# 2. Syncs the project's branding files (config.yaml, SOUL.md, skins/) into
#    the isolated HERMES_HOME runtime dir.
# 3. Boots the stripped hermes-core CLI with the Nightwing skin + persona +
#    plugins loaded.
#
# No custom web UI yet (build-order item 10) — this launches the rebranded
# interactive CLI, which is the one working entry point so far.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_CORE="$SCRIPT_DIR/hermes-core"
VENV="$SCRIPT_DIR/.venv-hermes-dev"
export HERMES_HOME="$SCRIPT_DIR/.hermes-nightwing"

# Context window fix (see hermes-core strip notes): Ollama silently defaults
# to 4096 tokens regardless of what a model actually supports, which breaks
# tool-calling on any real system prompt + tool schema payload. Must be set
# explicitly — do not remove this.
export OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-16384}"

log() { printf '\033[36m[nightwing]\033[0m %s\n' "$1"; }
err() { printf '\033[31m[nightwing]\033[0m %s\n' "$1" >&2; }

# ---------------------------------------------------------------------------
# 1. Local model server
# ---------------------------------------------------------------------------
if curl -s --max-time 2 http://127.0.0.1:11434/api/version > /dev/null 2>&1; then
    log "Ollama already running."
else
    log "Starting Ollama (context length: ${OLLAMA_CONTEXT_LENGTH})..."
    nohup ollama serve > "$SCRIPT_DIR/.ollama-serve.log" 2>&1 &
    for _ in $(seq 1 30); do
        if curl -s --max-time 1 http://127.0.0.1:11434/api/version > /dev/null 2>&1; then
            log "Ollama is up."
            break
        fi
        sleep 1
    done
    if ! curl -s --max-time 2 http://127.0.0.1:11434/api/version > /dev/null 2>&1; then
        err "Ollama did not come up — see $SCRIPT_DIR/.ollama-serve.log"
        exit 1
    fi
fi

# Verify the configured model is actually present — never auto-pull. A
# missing model in the field means the offline setup step was skipped, not
# something to silently fix by reaching out to the network.
CONFIGURED_MODEL="$(python3 -c "
import yaml
with open('$SCRIPT_DIR/config.yaml') as f:
    cfg = yaml.safe_load(f) or {}
print((cfg.get('model') or {}).get('default', ''))
" 2>/dev/null || true)"

if [ -n "$CONFIGURED_MODEL" ]; then
    if ! ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$CONFIGURED_MODEL"; then
        err "Configured model '$CONFIGURED_MODEL' is not pulled locally."
        err "This build never auto-downloads models (air-gapped by design)."
        err "Pull it during setup, while online, with: ollama pull $CONFIGURED_MODEL"
        exit 1
    fi
    log "Model '$CONFIGURED_MODEL' is present."
fi

# ---------------------------------------------------------------------------
# 2. Sync branding into the runtime HERMES_HOME
# ---------------------------------------------------------------------------
mkdir -p "$HERMES_HOME/skins" "$HERMES_HOME/plugins"
cp -f "$SCRIPT_DIR/config.yaml" "$HERMES_HOME/config.yaml"
cp -f "$SCRIPT_DIR/SOUL.md" "$HERMES_HOME/SOUL.md"
cp -f "$SCRIPT_DIR/skins/nightwing.yaml" "$HERMES_HOME/skins/nightwing.yaml"
log "Branding synced (config.yaml, SOUL.md, skins/nightwing.yaml)."

if [ -d "$SCRIPT_DIR/plugins" ] && [ -n "$(ls -A "$SCRIPT_DIR/plugins" 2>/dev/null)" ]; then
    for plugin_dir in "$SCRIPT_DIR"/plugins/*/; do
        [ -d "$plugin_dir" ] || continue
        rsync -a --delete "$plugin_dir" "$HERMES_HOME/plugins/$(basename "$plugin_dir")/" 2>/dev/null \
            || cp -rf "$plugin_dir" "$HERMES_HOME/plugins/"
    done
    log "Custom plugins synced: $(ls -1 "$SCRIPT_DIR/plugins" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 3. Boot the agent
# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
source "$VENV/bin/activate"
log "Launching Nightwing..."
# Deliberately do NOT cd here — stay in whatever directory the user invoked
# this from, so file tools resolve relative paths against their actual
# workspace. HERMES_CORE/VENV above are already absolute paths.
exec python "$HERMES_CORE/cli.py" "$@"
