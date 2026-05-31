# tmux-pane-fzf

Minimal tmux pane jumper: fuzzy-find any pane in the **current session** and switch to it. fzf runs inside a `display-popup`; no external state, no preview, single script.

## Install

```sh
mkdir -p ~/.tmux/scripts
cp pane-jump.sh ~/.tmux/scripts/
chmod +x ~/.tmux/scripts/pane-jump.sh
```

Add one line to `~/.tmux.conf` (the key is arbitrary — change `j` to anything you like):

```tmux
bind-key j display-popup -E -w 80% -h 60% "~/.tmux/scripts/pane-jump.sh"
```

Reload tmux:

```sh
tmux source-file ~/.tmux.conf
```

## Use

`prefix + j` → popup with every pane in the current session. Type to filter, **Enter** to jump, **Esc** to cancel.

Idle shells (`bash`/`zsh`/`fish`/`sh`/`dash`/`tcsh`/`ksh`) sink to the bottom of the initial list but are still matched while typing. Active panes (anything else running) appear on top.

## Requirements

- tmux 3.2+ (for `display-popup`)
- fzf
- POSIX `awk`, `sort`, `cut`

## Tweaks

- **Drop `pane_title`** from the display line (often a redundant hostname): inside `pane-jump.sh`'s awk block, comment the first `disp = …` line and uncomment the second.
- **Popup size**: change `-w 80% -h 60%` on the bind line.
- **Different key**: change `bind-key j` to any unused prefix key.
