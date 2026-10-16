#!/usr/bin/env bash
# One image-model restyle of a code-drawn figure, for the illustrate-pages workflow.
#
# Takes a PNG rendered from an asserted SVG and asks the local Codex CLI to redraw it in a house
# look with its built-in image_generation tool (billed to Robin's ChatGPT plan, not an API key).
# The prompt holds the content fixed: every label character for character, every level in the
# same relative place. The look comes from a style file the project profile supplies. Optionally
# writes a WebP beside the output.
#
# Makes no judgement about the result. A restyle can still misspell a label or shift a level;
# the workflow's check step compares it by eye against the source PNG and the page.
#
# Usage:
#   figure-restyle.sh <input.png> <out.png> --style-file FILE [--webp] [--webp-width N]
#                     [--webp-quality Q] [--log FILE] [--dry-run]
#
# Arguments:
#   <input.png>        the rendered source figure (must exist)
#   <out.png>          where to write the restyled PNG (parent dir must exist; written only on success)
#   --style-file FILE  one paragraph starting "STYLE:", the look (see config/illustrate-profiles/)
#   --webp             also write <out>.webp with cwebp
#   --webp-width N     WebP width in px, height keeps the aspect ratio (default 1400)
#   --webp-quality Q   cwebp -q value (default 82)
#   --log FILE         append one line per call: timestamp, input, output, exit
#   --dry-run          print the prompt and the codex command, call nothing
#
# Exit codes: 0 written; 1 bad arguments or missing tools; 2 codex failed or timed out;
# 3 codex finished but wrote no PNG.
#
# Knobs: FIGURE_RESTYLE_TIMEOUT seconds (default 600). A call takes about 1 to 3 minutes.
# Run several in parallel with `&` and `wait`; waves of about 5 stayed clear of rate limits.
set -euo pipefail

die() { local code=$1; shift; echo "figure-restyle: $*" >&2; exit "$code"; }

[[ $# -ge 2 ]] || die 1 "usage: figure-restyle.sh <input.png> <out.png> --style-file FILE [--webp] [--dry-run]"
in_png=$1; out_png=$2; shift 2
style_file=""; want_webp=0; webp_width=1400; webp_q=82; log_file=""; dry=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --style-file) style_file=${2:-}; shift 2 ;;
    --webp) want_webp=1; shift ;;
    --webp-width) webp_width=${2:-}; shift 2 ;;
    --webp-quality) webp_q=${2:-}; shift 2 ;;
    --log) log_file=${2:-}; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) die 1 "unknown argument: $1" ;;
  esac
done

[[ -s "$in_png" ]] || die 1 "input not found or empty: $in_png"
[[ -d "$(dirname "$out_png")" ]] || die 1 "output directory does not exist: $(dirname "$out_png")"
[[ -s "$style_file" ]] || die 1 "--style-file is required and must be non-empty"
case "$webp_width$webp_q" in *[!0-9]*) die 1 "--webp-width and --webp-quality must be whole numbers" ;; esac
timeout_s=${FIGURE_RESTYLE_TIMEOUT:-600}
case "$timeout_s" in ''|*[!0-9]*) die 1 "FIGURE_RESTYLE_TIMEOUT must be whole seconds" ;; esac

in_abs=$(cd "$(dirname "$in_png")" && pwd)/$(basename "$in_png")
style=$(tr '\n' ' ' < "$style_file")

# The content rules that held across 14 figures (rheos/cryptowatchtools#25, #31). Keep them
# generic: anything project-specific belongs in the style file.
rules="Use your image generation tool to redraw the attached figure in the style below, then save it in the current directory as ./restyled.png. ACCURACY IS CRITICAL: reproduce EVERY text label exactly as written in the input, character for character, including all numbers, units, symbols and punctuation; keep every line, level, zone, bar, arrow, box, candle and marker in the same relative position and proportion, so values sit at the same place relative to each other and to any axis; keep every panel and the same overall layout. Do not add, remove, shorten, reword or invent any text, number, label, title or figure number. If a label is long, wrap it, but keep every word. Landscape, matching the input's aspect ratio. Reply only with the file name."
prompt="$rules $style"

if [[ $dry -eq 1 ]]; then
  printf 'prompt: %s\n' "$prompt"
  # The prompt goes BEFORE -i: -i takes several files and swallows a trailing prompt as an image.
  printf 'command: codex exec --sandbox workspace-write --skip-git-repo-check -C <fresh empty dir> "<prompt>" -i %q\n' "$in_abs"
  exit 0
fi

command -v codex >/dev/null 2>&1 || die 1 "codex CLI not on PATH"
command -v perl >/dev/null 2>&1 || die 1 "perl is required for the timeout"
[[ $want_webp -eq 0 ]] || command -v cwebp >/dev/null 2>&1 || die 1 "cwebp not on PATH (brew install webp)"

work=$(mktemp -d "${TMPDIR:-/tmp}/figure-restyle.XXXXXX")
trap 'rm -rf "$work"' EXIT

log() { [[ -z "$log_file" ]] || printf '%s figure-restyle in=%s out=%s exit=%s\n' "$(date -u +%FT%TZ)" "$in_png" "$out_png" "$1" >> "$log_file"; }

set +e
(cd "$work" && perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$timeout_s" \
  codex exec --sandbox workspace-write --skip-git-repo-check -C "$work" "$prompt" -i "$in_abs" \
  > "$work/codex.log" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  log "$rc"
  [[ $rc -eq 142 ]] && die 2 "codex exceeded ${timeout_s}s"
  die 2 "codex exited $rc: $(tail -n 5 "$work/codex.log" | tr '\n' ' ')"
fi

# The model sometimes picks its own file name; take the newest PNG it wrote.
got=$(ls -t "$work"/*.png 2>/dev/null | head -n 1 || true)
if [[ -z "$got" || ! -s "$got" ]]; then log 3; die 3 "codex wrote no PNG: $(tail -n 5 "$work/codex.log" | tr '\n' ' ')"; fi
cp "$got" "$out_png"
if [[ $want_webp -eq 1 ]]; then
  cwebp -quiet -q "$webp_q" -resize "$webp_width" 0 "$out_png" -o "${out_png%.png}.webp"
fi
log 0
echo "$out_png"
