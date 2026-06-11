#!/usr/bin/env bash
#
# bluetooth-grab.sh — grab Bluetooth devices (Magic Keyboard, etc.) onto THIS Mac.
#
# Run this on the Mac you want the device to jump TO. It clears any stale bond,
# re-pairs, and connects. Mac-to-Mac only. Requires blueutil:
#     brew install blueutil
#
# Each run shows a picker of your paired devices — your last choice comes
# pre-selected, so it's usually just "OK". The selection is remembered in
# ~/.config/bluetooth-grab/devices.conf. Cancelling the picker does nothing.

set -euo pipefail

# GUI-launched .app bundles don't inherit a shell PATH, so Homebrew tools like
# blueutil won't be found. Put the usual Homebrew locations up front.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bluetooth-grab"
CONFIG_FILE="$CONFIG_DIR/devices.conf"
LOG_FILE="$CONFIG_DIR/last-run.log"

# The Bluetooth icon lives next to this script (in the .app's Resources, or in
# the project dir when run raw) — used to brand the result dialog.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_FILE="$SCRIPT_DIR/AppIcon.icns"

# Append a timestamped line to the log so we can see what happened on a click
# even when there's no terminal attached.
log() { mkdir -p "$CONFIG_DIR"; printf '%s  %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LOG_FILE"; }

# --- talking to the user ---------------------------------------------------
# When launched from the .app there's no terminal, so we talk via macOS
# notifications/dialogs. From a terminal we just print.

running_in_terminal() { [ -t 1 ]; }

alert() {
  local msg="$1"
  if running_in_terminal; then
    echo "$msg" >&2
  else
    osascript -e "display dialog \"$msg\" with title \"Bluetooth Grab\" \
      buttons {\"OK\"} default button \"OK\" with icon caution" >/dev/null 2>&1 || true
  fi
}

require_blueutil() {
  command -v blueutil >/dev/null 2>&1 && { log "blueutil ok: $(command -v blueutil)"; return; }
  log "blueutil NOT FOUND (PATH=$PATH)"
  alert "blueutil not found. Install it with:  brew install blueutil"
  exit 1
}

# --- device selection ------------------------------------------------------
# Print "address<TAB>name" for every paired device.
paired_devices() {
  blueutil --paired \
    | sed -nE 's/^address: ([^,]+),.*name: "([^"]*)".*$/\1\t\2/p'
}

# Show a picker of paired devices and save the chosen addresses to config.
# A picker label is "name  (address)" — keeps devices identifiable even when
# macOS hasn't resolved a friendly name, and makes the mapping unambiguous.
device_label() { printf '%s  (%s)' "$2" "$1"; }  # $1=addr $2=name

choose_devices() {
  local pairs saved as_list as_defaults default_clause chosen picked addr name label

  pairs="$(paired_devices)"
  log "choose_devices: paired lines=$(printf '%s' "$pairs" | grep -c .)"
  [ -n "$pairs" ] || { alert "No paired Bluetooth devices found. Pair your device first."; exit 1; }

  saved="$(saved_addresses)"   # so we can pre-tick the current selection

  # Build AppleScript list literals: all device labels, plus the labels of
  # devices already saved (shown pre-selected in the picker).
  as_list=""; as_defaults=""
  while IFS=$'\t' read -r addr name; do
    label="$(device_label "$addr" "$name")"
    label="${label//\\/\\\\}"; label="${label//\"/\\\"}"
    as_list+="\"$label\", "
    printf '%s\n' "$saved" | grep -qxF "$addr" && as_defaults+="\"$label\", "
  done <<< "$pairs"
  as_list="${as_list%, }"
  as_defaults="${as_defaults%, }"

  default_clause=""
  [ -n "$as_defaults" ] && default_clause="default items {$as_defaults}"
  log "choose_devices: showing picker (defaults=[$as_defaults])"

  chosen="$(osascript <<EOF 2>>"$LOG_FILE"
set deviceList to {$as_list}
set chosenItems to choose from list deviceList with prompt "Grab which device(s) onto this Mac?" with title "Bluetooth Grab" $default_clause with multiple selections allowed
if chosenItems is false then return "__CANCELLED__"
set AppleScript's text item delimiters to linefeed
return chosenItems as text
EOF
)"

  log "choose_devices: picker returned [$chosen]"
  [ "$chosen" = "__CANCELLED__" ] && { log "choose_devices: cancelled, exiting"; exit 0; }

  # Map chosen labels back to addresses; save one address per line.
  mkdir -p "$CONFIG_DIR"
  : > "$CONFIG_FILE"
  while IFS= read -r picked; do
    [ -n "$picked" ] || continue
    while IFS=$'\t' read -r addr name; do
      [ "$(device_label "$addr" "$name")" = "$picked" ] && echo "$addr" >> "$CONFIG_FILE"
    done <<< "$pairs"
  done <<< "$chosen"
  return 0   # the trailing while-loop exits non-zero (read hits EOF); under
             # `set -e` that would abort the caller, so force success here.
}

# Read saved addresses (skipping blanks and comments).
saved_addresses() {
  [ -f "$CONFIG_FILE" ] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$CONFIG_FILE" || true
}

# --- the grab --------------------------------------------------------------
# Re-pairing a device that's stuck on another host can make blueutil block
# forever. Run every Bluetooth call under a hard timeout so a stuck pairing
# window surfaces as a clear failure instead of an infinite hang.
BT_TIMEOUT="${BT_TIMEOUT:-25}"
bt() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$BT_TIMEOUT" blueutil "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$BT_TIMEOUT" blueutil "$@"
  else
    blueutil "$@"
  fi
}

grab_device() {
  local addr="$1"

  # Already connected to THIS Mac? Nothing to grab — don't tear down a working
  # connection (and don't risk hanging trying to re-pair a connected device).
  is_connected "$addr" && return 0

  # Clear any stale pairing on this Mac so we re-establish cleanly.
  bt --unpair "$addr" >/dev/null 2>&1 || true
  sleep 1

  # Re-pair. A Magic Keyboard stores only ONE host bond, so if it's still
  # actively connected to the other Mac it won't be in its pairable window —
  # that's when you flick its power switch off/on.
  bt --pair "$addr" >/dev/null 2>&1 || return 1
  sleep 2

  bt --connect "$addr" >/dev/null 2>&1 || return 1
}

# Ask Bluetooth directly whether the device is connected right now.
is_connected() { [ "$(blueutil --is-connected "$1" 2>/dev/null)" = "1" ]; }

# Connecting can lag a moment, so poll for a few seconds before giving up.
wait_connected() {
  local addr="$1" i
  for i in 1 2 3 4 5 6; do
    is_connected "$addr" && return 0
    sleep 1
  done
  return 1
}

name_for_addr() {
  paired_devices | awk -F'\t' -v a="$1" '$1 == a { print $2; exit }'
}

# Always-visible result dialog (vs. an easy-to-miss notification).
show_result() {  # $1=report text  $2="1" if any device failed
  local report="$1" failed="$2" icon="note" rc esc icon_clause
  log "show_result (failed=$failed): $(printf '%s' "$report" | tr '\n' '|')"
  if running_in_terminal; then printf '%s\n' "$report"; return; fi
  [ "$failed" = "1" ] && icon="caution"
  # Brand the dialog with our Bluetooth icon when it's available; otherwise
  # fall back to the system note/caution icon.
  if [ -f "$ICON_FILE" ]; then
    icon_clause="with icon (POSIX file \"$ICON_FILE\")"
  else
    icon_clause="with icon $icon"
  fi
  esc="${report//\\/\\\\}"; esc="${esc//\"/\\\"}"
  if osascript -e "display dialog \"$esc\" with title \"Bluetooth Grab\" \
    buttons {\"OK\"} default button \"OK\" $icon_clause" >/dev/null 2>>"$LOG_FILE"; then
    rc=0
  else
    rc=$?
  fi
  log "result dialog osascript rc=$rc"
}

# --- main ------------------------------------------------------------------
main() {
  log "=== run started (terminal=$(running_in_terminal && echo yes || echo no)) ==="
  require_blueutil

  # Always show the picker (with the current selection pre-ticked), then grab.
  # Cancelling the picker does nothing.
  choose_devices
  log "after picker; saved=[$(saved_addresses | tr '\n' ',')]"

  local addrs addr nm report="" any_fail=0
  addrs="$(saved_addresses)"
  [ -n "$addrs" ] || { alert "No devices selected."; exit 1; }

  while IFS= read -r addr; do
    [ -n "$addr" ] || continue
    nm="$(name_for_addr "$addr")"; [ -n "$nm" ] || nm="$addr"

    log "grabbing $addr ($nm); already connected=$(is_connected "$addr" && echo yes || echo no)"
    grab_device "$addr" || true     # verify the real state below regardless

    if wait_connected "$addr"; then
      report+="✓  $nm — connected"$'\n'
    else
      report+="✗  $nm — NOT connected"$'\n'
      any_fail=1
    fi
  done <<< "$addrs"

  if [ "$any_fail" = "1" ]; then
    report+=$'\n'"If a device failed: flick its power switch off/on, then click Bluetooth Grab again."
  fi

  show_result "$report" "$any_fail"
  [ "$any_fail" = "1" ] && exit 1 || exit 0
}

main "$@"
