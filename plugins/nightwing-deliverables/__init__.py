"""nightwing-deliverables plugin — MRPL-specific document generation.

Registers ``generate_approval_note``: a deterministic tool (plain
python-docx calls, not LLM-generated markup) that turns structured findings
into a real .docx approval note. Complements the existing ``docx`` skill
rather than replacing it — this tool handles the one recurring MRPL
document shape; the docx skill still covers everything else.

Also registers a matching skill (``nightwing-deliverables:approval-note``)
so the agent knows when to reach for the tool instead of freehand
python-docx via execute_code.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict

from . import approval_note as _an


def _handle_generate_approval_note(args: Dict[str, Any], **kw) -> str:
    from tools.registry import tool_error

    if not isinstance(args, dict):
        return tool_error("generate_approval_note: missing arguments")

    findings = args.get("findings")
    if isinstance(findings, str):
        # Tolerate a single string — split on newlines rather than reject.
        findings = [line.strip() for line in findings.splitlines() if line.strip()]

    try:
        from hermes_constants import get_hermes_home
        hermes_home = str(get_hermes_home())
    except Exception:
        hermes_home = None

    result = _an.generate_approval_note(
        output_path=args.get("output_path", "approval_note.docx"),
        subject=args.get("subject", ""),
        findings=findings or [],
        recommendation=args.get("recommendation", ""),
        hermes_home=hermes_home,
        ref_no=args.get("ref_no"),
        department=args.get("department", ""),
        prepared_by=args.get("prepared_by", ""),
        source_document=args.get("source_document", ""),
    )
    return json.dumps(result)


_SCHEMA = {
    "type": "object",
    "properties": {
        "output_path": {
            "type": "string",
            "description": "Where to save the .docx file (relative paths resolve against the current working directory).",
        },
        "subject": {
            "type": "string",
            "description": "One-line subject of the approval note.",
        },
        "findings": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Key findings, one per list item — pulled from the source inspection report/document.",
        },
        "recommendation": {
            "type": "string",
            "description": "The recommended action or approval being requested.",
        },
        "ref_no": {
            "type": "string",
            "description": "Reference number. Auto-generated (NW/AN/<year>/<seq>) if omitted.",
        },
        "department": {
            "type": "string",
            "description": "Originating department, if known.",
        },
        "prepared_by": {
            "type": "string",
            "description": "Name of the preparer, if known.",
        },
        "source_document": {
            "type": "string",
            "description": "Name/reference of the source document this note is based on (e.g. the inspection report filename).",
        },
    },
    "required": ["output_path", "subject", "findings", "recommendation"],
}


def register(ctx) -> None:
    ctx.register_tool(
        name="generate_approval_note",
        toolset="hermes-cli",
        schema=_SCHEMA,
        handler=_handle_generate_approval_note,
        description="Generate an MRPL-style approval note as a real .docx file from structured findings.",
        emoji="📝",
    )

    skill_path = Path(__file__).parent / "skills" / "approval-note" / "SKILL.md"
    if skill_path.exists():
        ctx.register_skill(
            name="approval-note",
            path=skill_path,
            description="How and when to use generate_approval_note for MRPL approval notes.",
        )
