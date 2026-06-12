# Workflow: copy-review

**When to use:** any user-facing text needs a voice / tone / audience check before it
ships — marketing copy, app microcopy, emails, error messages, release notes, a bio, a
post. Point it at a blob of copy.

**Type:** mixed (it reviews and hands back fixed copy)

**Inputs:** the copy to review; who the audience is and where it appears (infer if not given).

**Outputs:** Voice's per-lens findings, a revised version, and a SHIP / REVISE verdict,
returned to you. Nothing is written to spec/plan files.

**Leans on skills:** `humanizer`, `spiral-dynamics`.

## Steps

1. **The Counselor** (Voice, **sonnet**, mode: review) — load the humanizer and spiral-dynamics
   skills, review the copy through the four lenses (voice / AI-tells, audience fit,
   overwhelm / clarity, honesty), and return findings + revised copy + verdict.

This is a single-agent workflow. The Counselor can also drop in as a final gate at the end of
any workflow that produces user-facing content. For framing a message *before* it's
written, use `message-framing` (The Counselor in frame mode).
