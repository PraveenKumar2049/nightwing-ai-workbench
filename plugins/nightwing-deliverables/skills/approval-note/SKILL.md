---
name: approval-note
description: "Generate an MRPL approval note as a real .docx file from structured findings."
version: 1.0.0
author: Nightwing (MRPL, SIH 2026)
metadata:
  hermes:
    tags: [MRPL, Approval-Note, Deliverable, Word]
    related_skills: [docx, ocr-and-documents]
---

# MRPL Approval Note

Use this whenever the user asks for an "approval note," "approval memo," or
similar formal sign-off document — especially the read-a-report-then-draft-a-note
workflow (e.g. after extracting findings from a scanned inspection report via
the `ocr-and-documents` skill).

## Don't hand-roll this with python-docx

Call the tool named `generate_approval_note` directly (it's a real tool in
your tool list, not something you need to load or search for). It produces a consistent,
correctly-formatted document (reference block, findings list, recommendation,
sign-off table) every time — freehand `execute_code` + python-docx for this
one recurring shape is both slower and more error-prone than the tool.

For any *other* Word document shape, use the `docx` skill as normal —
this tool only covers the approval-note format.

## Workflow

1. If the source is a scanned/PDF report, extract text first via the
   `ocr-and-documents` skill (or `read_file` if it's already plain text).
2. Pull out: subject, key findings (as a clean list — one point per finding,
   not raw paragraphs), and a recommendation. Don't invent findings that
   aren't in the source — if something is unclear, say so in the findings
   list rather than guessing.
3. Call `generate_approval_note`:

```
generate_approval_note(
    output_path="approval_note.docx",
    subject="<one line>",
    findings=["<finding 1>", "<finding 2>", ...],
    recommendation="<the recommended action>",
    source_document="<name of the report this is based on, if any>",
)
```

`ref_no`, `department`, and `prepared_by` are optional — pass them if the
user supplied them, otherwise leave them out (ref_no auto-generates).

4. Report the saved path back to the user. The signature block is left
   blank for physical/digital sign-off — do not fabricate names or dates
   into it.

## Note on the template

The generated layout is a generic starter format, not MRPL's actual
letterhead — flag this to the user if they need the real house template
before relying on the output for an actual approval workflow.
