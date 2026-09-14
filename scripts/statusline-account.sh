#!/usr/bin/env bash
# statusline-account.sh — resolve which Claude account a session is bound to,
# and render a short colour/emoji badge for it.
#
# Sourced by statusline-usage.sh; also runnable standalone for debugging:
#   echo '{"session_id":"abc"}' | scripts/statusline-account.sh
#
# WHY THIS EXISTS
# ---------------
# Claude Code's statusLine payload carries no account field. Verified against
# the payload constructor in the 2.1.257 bundle: it returns session/model/
# workspace/version/output_style/cost/context_window/rate_limits/vim/agent/
# remote/pr/worktree and nothing identifying the logged-in account. So when a
# machine juggles several accounts (claude-swap and friends), a session gives
# no visible clue which quota it is actually spending.
#
# TWO CASES, AND WHY THE SECOND NEEDS A CACHE
# -------------------------------------------
# 1. CLAUDE_CONFIG_DIR is set — the session was launched into an isolated
#    per-account profile (`cswap run <acct>`). That directory IS the binding,
#    it cannot change under a running session, so reading it is always right.
#
# 2. CLAUDE_CONFIG_DIR is unset — the session uses the shared ~/.claude
#    profile. Reading it live is a TRAP: switching accounts rewrites that file
#    while already-running sessions keep the credentials they started on. A
#    live read would relabel every old session to the new account and point at
#    the wrong quota bar. So resolve ONCE per session_id and cache the answer.
#    A session holds its account for life; the cache mirrors that.
#
# Everything fails safe. No account, no jq, no config, unreadable file: print
# nothing and let the caller's status line render exactly as it did before.

set -uo pipefail

BADGE_CONFIG="${NOVADIEM_ACCOUNT_BADGES:-$HOME/.novadiem/account-badges.json}"
CACHE_DIR="${NOVADIEM_SESSION_ACCOUNTS_DIR:-$HOME/.novadiem/session-accounts}"
CACHE_TTL_DAYS="${NOVADIEM_SESSION_ACCOUNTS_TTL_DAYS:-14}"

# Palette for accounts with no configured badge. Stable per email (hashed), so
# an unconfigured account still gets a consistent colour instead of a new one
# each render. Emoji and the matching 256-colour code travel in pairs.
_FALLBACK_EMOJI=(🔵 🟢 🟣 🟠 🔴 🟡 🟤 ⚪)
_FALLBACK_COLOR=(39 42 141 214 203 220 130 245)

# Read .oauthAccount.emailAddress out of the first candidate that actually
# carries one.
#
# The field's home differs by profile, and a file existing is NOT evidence it
# holds the account: the DEFAULT profile keeps it in ~/.claude.json (large,
# live), while ~/.claude/.claude.json can exist as a small stub with no
# oauthAccount at all. Stopping at the first readable file would resolve that
# stub to "unknown" and hide a perfectly available answer — so keep walking
# until the field is found.
_account_email_from_candidates() {
  local candidate email
  for candidate in "$@"; do
    [ -r "$candidate" ] || continue
    email="$(jq -r '.oauthAccount.emailAddress // empty' "$candidate" 2>/dev/null)"
    if [ -n "$email" ]; then
      printf '%s' "$email"
      return 0
    fi
  done
  return 1
}

# Candidate list for the account file, in priority order.
#
# When CLAUDE_CONFIG_DIR is set the search is DELIBERATELY confined to it: that
# profile is the session's binding, and falling back to $HOME on a miss would
# report the default profile's account — precisely the wrong-account answer
# this script exists to prevent. Printing nothing beats printing a lie.
_account_candidates() {
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_CONFIG_DIR/.claude.json"
  else
    printf '%s\n' "$HOME/.claude.json" "$HOME/.claude/.claude.json"
  fi
}

# Resolve the account for this session, honouring the two cases above.
# Usage: statusline_account <session_id>
statusline_account() {
  local session_id="${1:-}"
  local email cache_file tmp
  local candidates=()

  command -v jq >/dev/null 2>&1 || return 0
  while IFS= read -r line; do candidates+=("$line"); done < <(_account_candidates)

  # Case 1: isolated profile. The dir is the binding and cannot change under a
  # running session, so read it live — no cache needed.
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    _account_email_from_candidates "${candidates[@]}" || true
    return 0
  fi

  # Case 2: shared profile with no session id to key on — best effort only.
  if [ -z "$session_id" ]; then
    _account_email_from_candidates "${candidates[@]}" || true
    return 0
  fi

  # Case 2: shared profile, resolve once and remember.
  cache_file="$CACHE_DIR/$session_id"
  if [ -r "$cache_file" ]; then
    cat "$cache_file" 2>/dev/null
    return 0
  fi

  email="$(_account_email_from_candidates "${candidates[@]}")" || return 0
  [ -n "$email" ] || return 0

  if mkdir -p "$CACHE_DIR" 2>/dev/null; then
    tmp="$(mktemp "$CACHE_DIR/.tmp.XXXXXX" 2>/dev/null)" || tmp=""
    if [ -n "$tmp" ]; then
      printf '%s' "$email" >"$tmp" 2>/dev/null
      # -n: never clobber. A concurrent render that got there first wins, and
      # both wrote the same value anyway.
      mv -n "$tmp" "$cache_file" 2>/dev/null
      rm -f "$tmp" 2>/dev/null
    fi
    # Prune here rather than on every render: this branch runs once per
    # session, so the sweep costs nothing per status line.
    find "$CACHE_DIR" -type f -mtime "+$CACHE_TTL_DAYS" -delete 2>/dev/null
  fi

  printf '%s' "$email"
}

# Render the badge for an email: an emoji plus a short coloured label.
# Looks up ~/.novadiem/account-badges.json first:
#
#   { "accounts": { "someone@example.com": { "emoji": "🔵",
#                                            "label": "work",
#                                            "color": 39 } } }
#
# `color` is a 256-colour code and is optional; label defaults to the local
# part of the address. Deliberately a LOCAL file, not a table in this repo:
# this repo is public and account addresses are not ours to publish.
statusline_account_badge() {
  local email="${1:-}"
  local emoji label color idx sum ch

  [ -n "$email" ] || return 0

  if [ -r "$BADGE_CONFIG" ] && command -v jq >/dev/null 2>&1; then
    emoji="$(jq -r --arg e "$email" '.accounts[$e].emoji // empty' "$BADGE_CONFIG" 2>/dev/null)"
    label="$(jq -r --arg e "$email" '.accounts[$e].label // empty' "$BADGE_CONFIG" 2>/dev/null)"
    color="$(jq -r --arg e "$email" '.accounts[$e].color // empty' "$BADGE_CONFIG" 2>/dev/null)"
  fi

  if [ -z "${emoji:-}" ] || [ -z "${color:-}" ]; then
    # Stable hash -> palette slot, so an unconfigured account still reads the
    # same way every render.
    sum=0
    while IFS= read -r -n1 ch; do
      [ -n "$ch" ] || continue
      sum=$(( (sum + $(printf '%d' "'$ch")) % 997 ))
    done <<<"$email"
    idx=$(( sum % ${#_FALLBACK_EMOJI[@]} ))
    emoji="${emoji:-${_FALLBACK_EMOJI[$idx]}}"
    color="${color:-${_FALLBACK_COLOR[$idx]}}"
  fi

  label="${label:-${email%%@*}}"

  printf '\033[38;5;%sm%s %s\033[0m' "$color" "$emoji" "$label"
}

# Standalone debug mode: only when executed directly, never when sourced.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  _payload="$(cat 2>/dev/null || true)"
  _sid=""
  if command -v jq >/dev/null 2>&1 && [ -n "$_payload" ]; then
    _sid="$(printf '%s' "$_payload" | jq -r '.session_id // empty' 2>/dev/null)"
  fi
  _email="$(statusline_account "$_sid")"
  printf 'session_id=%s\naccount=%s\nbadge=%s\n' \
    "${_sid:-(none)}" "${_email:-(unresolved)}" "$(statusline_account_badge "$_email")"
fi
