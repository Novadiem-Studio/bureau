#!/bin/bash
# Sync canon docs + reference images into a flat folder for ChatGPT uploads.
# ChatGPT has no file system, so everything lands in one directory; nested
# paths are flattened with a prefix (conductor-motif/x.png -> conductor-motif-x.png).
# Run after locking a new reference or editing a canon doc.
set -euo pipefail

FRAMEWORK="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT="$FRAMEWORK/../chatgpt-export"
mkdir -p "$EXPORT"

# Canon docs
cp "$FRAMEWORK/LORE.md"                                   "$EXPORT/"
cp "$FRAMEWORK/VISUAL-CANON.md"                           "$EXPORT/"
cp "$FRAMEWORK/VISUAL-SYSTEM.md"                          "$EXPORT/"
cp "$FRAMEWORK/reference/designer-handoff-trilogy.md"     "$EXPORT/"
cp "$FRAMEWORK/../../novadiem.com/docs/brand-brief-sacred-instrument.md" "$EXPORT/"

# Character + emblem references
cp "$FRAMEWORK/reference/novadiem-emblem.svg"             "$EXPORT/"
cp "$FRAMEWORK/reference/visionary-reference.png"         "$EXPORT/"
cp "$FRAMEWORK/reference/conductor-reference.png"         "$EXPORT/"
cp "$FRAMEWORK/reference/conductor-model-sheet.png"       "$EXPORT/"
cp "$FRAMEWORK/reference/conductor-spec-sheet-v1.png"     "$EXPORT/"
cp "$FRAMEWORK/reference/visual-spec-sheet-v1.png"        "$EXPORT/"

# Conductor motif plates (flattened)
for f in "$FRAMEWORK"/reference/conductor-motif/*.png; do
  cp "$f" "$EXPORT/conductor-motif-$(basename "$f")"
done

# Locked posters
cp "$FRAMEWORK"/reference/the-*-v1*.png "$EXPORT/" 2>/dev/null || true

echo "Synced to $EXPORT:"
ls -1 "$EXPORT"
