# Nightwing

**A sovereign, on-premise agentic AI workbench — built for Smart India Hackathon 2026, Problem Statement SIH26117.**

> 🎥 Demo video: _[link goes here]_

## The pitch

MRPL needs an AI workbench for confidential industrial work — reading inspection reports, drafting approval notes, running calculations, searching internal manuals — that can run entirely on the organization's own hardware, with a hard guarantee that nothing leaves the building. Off-the-shelf hosted AI tools can't make that guarantee. General-purpose local LLM chat UIs don't act as *agents*: they don't plan multi-step work, call tools, read scanned/handwritten documents, or produce real deliverable files.

Nightwing is a single, sovereign, agentic workbench that does all of that, running locally on-prem against an open-weight model. It:

- **Runs 100% offline.** No external network call is made at any point during operation — verified with a genuine kernel network-namespace isolation test (zero external interface, not just DNS blocking), running the full model server + agent together and confirming the agent still completes real work.
- **Acts as a real agent.** Plans multi-step work, calls local tools (file I/O, sandboxed code execution, document generation), and iterates instead of one-shotting an answer.
- **Produces real deliverables.** Reads a scanned/text inspection report, pulls out findings, and drafts a formal approval note as an actual `.docx` file — not just a chat reply.
- **Is genuinely multimodal.** Runs on Gemma 4 (Effective-2B variant), a natively multimodal open-weight model, for text and vision tasks.
- **Never phones home.** Every dependency that could reach the internet was audited and either removed outright or hard-disabled via config — not just left at its default.

## What this is built on, and why

Nightwing is a fork of [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) (MIT license) — chosen because it already has a real agent loop, a pluggable model-backend transport layer, a tool-calling framework, and bundled skills for PDF/DOCX/PPTX generation and OCR that map directly onto this problem statement's requirements.

**Two hard rules governed the whole build:**

1. **`hermes-core/` internals are never hand-edited for new functionality.** Rebranding goes through Hermes' own skin engine (`skins/nightwing.yaml`) and persona file (`SOUL.md`), never by touching source. New functionality goes through Hermes' own plugin system (`plugins/`). This keeps the fork rebaseable against upstream security fixes, and is a defensible engineering story: we extended Hermes through its own supported extension points, not by hacking the vendor's source.
   - The only exceptions are a handful of narrow, necessary bug fixes to `hermes-core/` — each one is a one- or two-line defensive-import guard needed because a file the fix touches still (correctly) references a module we deleted elsewhere in the strip-down. These are documented inline with `# Nightwing strip:` comments everywhere they occur, so they're easy to find, audit, or drop when rebasing against upstream.
2. **Every network-capable code path is either deleted or explicitly disabled**, not just left unconfigured. "Off by default" isn't good enough for an air-gap claim — see below.

## What was stripped, and why

Hermes-agent ships an enormous surface area for a general-purpose, cloud-connected, multi-platform agent. Almost none of that belongs in an air-gapped, single-purpose industrial workbench. Roughly 2,300+ files were removed.

| Category | What was cut | Why |
|---|---|---|
| **Cloud model providers** | 32 of 34 provider plugins (`plugins/model-providers/`) — OpenAI, Anthropic, Gemini, every hosted API | Only `custom` (talks to a local OpenAI-compatible server — Ollama) is needed. Every other entry is a live path to a cloud API. |
| **Credential/proxy plumbing** | `agent/secret_sources/`, `agent/proxy_sources/` (Bitwarden, 1Password, egress-firewall auto-installer) | Manages *external* credentials for cloud services we no longer use; the egress-firewall component also auto-downloaded a binary from GitHub on first use. |
| **Browser & web** | All browser automation tools, `web_search`/`web_extract`, and their backing plugins (`plugins/browser/`, `plugins/web/`) | Direct internet access by design — the opposite of the point. |
| **Messaging platforms** | Telegram, Discord, Slack, WhatsApp, and 17 more (`plugins/platforms/`), plus the whole `gateway/` messaging system | Irrelevant to an internal engineering tool; each one is a live external connection. |
| **Cloud generation tools** | Image/video generation, text-to-speech, voice/wake-word, transcription | All cloud-API-backed; none apply to a document-and-code workbench. |
| **External memory backends** | 7 of 8 backends under `plugins/memory/` (Hindsight, Mem0, Honcho, etc.) | Local file-based memory is built in and sufficient; the rest are cloud services. |
| **Misc platform integrations** | Home Assistant, Spotify, Feishu, Kanban, Microsoft Graph, X/Twitter search, computer-use (macOS) | Out of scope, each with its own external dependency. |
| **Repo infrastructure** | `web/`, `website/`, `locales/`, `acp_adapter/`, dev-only benchmark scripts | Marketing site, i18n, IDE integration, and internal dev tooling — not part of the shipped product. |

**Kept, and why:** the file tools, sandboxed `terminal`/`process`/`execute_code`, local `memory`, `session_search`, the skill system, and the `pdf`/`docx`/`powerpoint`/`ocr-and-documents`/`xlsx` skills — all local-only, and exactly what the problem statement's deliverable-generation and OCR requirements need. One skill (`ocr-and-documents`) had a "try `web_extract` first" default that was rewritten to local-only.

**Also disabled, not just left at default:**
- `security.tirith_enabled: false` — stops an auto-download of a security-scanner binary from GitHub on first tool call
- `security.allow_lazy_installs: false` — stops runtime auto-pip-install of optional backend packages
- No `fallback_providers` configured — a local model error surfaces as an error, never silently reroutes to a cloud provider
- `OLLAMA_CONTEXT_LENGTH` explicitly set — Ollama silently defaults to a 4096-token context regardless of what the model supports, which breaks tool-calling once a real system prompt + tool schema is in play; this must never be left implicit

## Model

Configured for **Gemma 4 (Effective-2B)** via Ollama — natively multimodal, ~2B effective parameters via elastic/MatFormer execution, fits comfortably on modest GPU hardware. Qwen3.5-4B is kept as a documented fallback/comparison candidate; both should be re-benchmarked against real scanned documents/drawings before finalizing either one for a production deployment.

## Running it

Prerequisites: [Ollama](https://ollama.com) installed, Python 3.11+, [`uv`](https://github.com/astral-sh/uv).

```bash
# 1. Set up the Python environment (one-time)
uv venv .venv-hermes-dev --python 3.11
source .venv-hermes-dev/bin/activate
cd hermes-core && uv pip install -e ".[all,dev]" && cd ..
uv pip install python-docx python-pptx pymupdf pymupdf4llm pypdf reportlab pdfplumber openpyxl

# 2. Pull the model (one-time, requires network — this is the only step that does)
ollama pull gemma4:e2b

# 3. Launch
./start.sh
```

`start.sh` checks/starts Ollama (with the required context-length setting), verifies the model is present (never auto-pulls — this build assumes air-gapped operation from here on), syncs branding into an isolated `HERMES_HOME`, and boots the agent. No custom web UI yet — this launches the branded interactive CLI.

Try it against the included example:
```bash
cd test-workspace
../start.sh
# then type: Read inspection_report.txt and draft a formal approval note
# summarizing the key findings and recommendation. Save it as approval_note.docx.
```

## Project layout

```
nightwing-public/
├── start.sh              # single entry point
├── hermes-core/          # stripped hermes-agent fork — internals untouched except
│                          # documented "# Nightwing strip:" defensive-import fixes
├── plugins/               # custom additions, via Hermes' own plugin system
│   └── nightwing-deliverables/   # MRPL approval-note generation
├── skins/nightwing.yaml   # visual rebrand (skin engine)
├── SOUL.md                 # persona / identity
├── config.yaml              # local-only provider config, disabled fallbacks
└── test-workspace/         # example input + generated output
```

## Status

Working: baseline agent loop, full strip-down, network-isolation verification, skin/persona rebrand, launcher, and one complete demo scenario (scanned/text report → real approval-note `.docx`) via the interactive CLI.

Not yet built: the custom web UI, the multimodal/vision ingestion plugin, the task-routing classifier, and the local RAG/knowledge-base plugin. The `generate_approval_note` plugin tool is implemented and correctly resolves into the toolset programmatically, but doesn't yet reliably reach the live CLI session — currently falls back to `execute_code` + `python-docx`, which produces equivalent output.

## License

`hermes-core/` retains its original [MIT License](hermes-core/LICENSE), Copyright (c) 2025 Nous Research, unmodified. Nightwing's own additions (this README, `SOUL.md`, `skins/`, `plugins/`, `start.sh`, `config.yaml`) are released under the same [MIT License](LICENSE) for consistency.
