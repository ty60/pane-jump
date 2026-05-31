#!/usr/bin/env bash
# pane-jump.sh — Fuzzy-find and switch to a pane in the current tmux session.
#
# Launched from tmux's display-popup. Lists every pane in the current session,
# lets the user pick one with fzf, and jumps to it via select-window +
# select-pane. Idle shells sink to the bottom of the initial list but remain
# searchable.
#
# Install: chmod +x ~/.tmux/scripts/pane-jump.sh
# Bind:    bind-key f display-popup -E -w 80% -h 60% "~/.tmux/scripts/pane-jump.sh"
#
# Perf note (startup/dismiss latency): this script is NOT the bottleneck. Its
# data pipeline (list-panes + awk + sort) runs in ~15-20ms, and the popup shell
# is non-interactive/non-login so there is no rc-sourcing cost. Two things
# dominate perceived lag, both outside this file:
#   1. ESC-to-dismiss delay = tmux `escape-time` (set it low, e.g.
#      `set -sg escape-time 10`; a conf edit needs `source-file` to take effect).
#   2. Intermittent ~200-400ms spike on the FIRST tmux op after the machine has
#      been idle — affects every tmux command equally, independent of this
#      script. Likely macOS App Nap / process throttling on the tmux server.

set -u

TAB=$'\t'

# Colon-free byte range covering every control char (0x01-0x1F plus 0x7F).
# We can't use #{s|[[:cntrl:]]|...|} below: the colons inside the POSIX class
# collide with the substitution modifier's ':' separator, so tmux (3.5a) fails
# to compile the regex and silently yields an empty string. This range strips
# the same characters — including TAB and newline — without any colons.
CNTRL=$'[\001-\037\177]'

# Pull every pane in the current session as TAB-separated raw fields:
#   cmd, pane_id, window_id, window_index, pane_index, path, title
# pane_title and pane_current_path are attacker-influenceable (any process in
# any pane can set its own title via OSC, and cwd can in principle contain
# control bytes). Strip control chars at the tmux source so a crafted newline
# cannot split one row into two — otherwise an attacker can inject a forged
# row that, when selected, hijacks select-pane to a pane they choose.
panes=$(tmux list-panes -s -F \
  "#{pane_current_command}${TAB}#{pane_id}${TAB}#{window_id}${TAB}#{window_index}${TAB}#{pane_index}${TAB}#{s|${CNTRL}| |:pane_current_path}${TAB}#{s|${CNTRL}| |:pane_title}" \
  2>/dev/null) || exit 0

[ -z "$panes" ] && exit 0

# Re-emit as: sort_key \t pane_id \t window_id \t display
# sort_key = 0 (active) | 1 (idle shell). The display column contains no tabs,
# so fzf's --delimiter / --with-nth can cleanly hide the first three columns.
formatted=$(printf '%s\n' "$panes" | awk -F'\t' -v OFS='\t' '
  BEGIN {
    split("bash zsh fish sh dash tcsh ksh", a, " ");
    for (i in a) shells[a[i]] = 1;
  }
  # Defence-in-depth alongside the tmux-side control-char strip: drop any
  # malformed row (e.g. a fragment left by an injected newline) and require
  # the ID fields to match tmux ID syntax. A forged row that survives this
  # must still name a real pane_id, which limits damage to redirection
  # within panes that already exist on the server.
  NF != 7 { next }
  $2 !~ /^%[0-9]+$/ { next }
  $3 !~ /^@[0-9]+$/ { next }
  {
    cmd=$1; pid=$2; wid=$3; widx=$4; pidx=$5; path=$6; title=$7;
    # Strip remaining control characters so a crafted title cannot move the
    # cursor, repaint the popup, or otherwise spoof the fzf UI.
    gsub(/[[:cntrl:]]/, "?", cmd);
    gsub(/[[:cntrl:]]/, "?", path);
    gsub(/[[:cntrl:]]/, "?", title);
    key = (cmd in shells) ? 1 : 0;
    # Display: "win:pane cmd  path  (title)".
    # pane_title often defaults to the hostname and is mostly noise — to drop
    # it, comment the line below and uncomment the next one.
    # disp = widx ":" pidx " " cmd "  " path "  (" title ")";
    disp = widx ":" pidx " " cmd "  " path;
    print key, pid, wid, disp;
  }
')

# Stable sort: active panes first, idle shells last; preserve tmux's natural
# ordering within each group.
sorted=$(printf '%s\n' "$formatted" | sort -s -t"$TAB" -k1,1n)

# Hide the first three (control) columns from fzf. Leave fzf's relevance sort
# on so query-time matches rank well — i.e. deliberately no --no-sort.
selected=$(printf '%s\n' "$sorted" | fzf \
  --delimiter="$TAB" \
  --with-nth=4.. \
  --reverse \
  --prompt='pane> ') || exit 0

[ -z "$selected" ] && exit 0

pane_id=$(printf '%s' "$selected" | cut -f2)
window_id=$(printf '%s' "$selected" | cut -f3)

# pane_id/window_id are server-wide unique, so no session qualifier needed.
tmux select-window -t "$window_id"
tmux select-pane -t "$pane_id"
