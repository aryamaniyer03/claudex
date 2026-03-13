# Claudex

A native macOS terminal session manager built for Claude Code. Manage all your Claude Code sessions in a single window with persistent tmux sessions, conversation history browsing, and seamless session import.

## Features

- **Multi-session workspace** — Run multiple terminal sessions side by side with instant switching (Cmd+Up/Down, Cmd+1-9)
- **Persistent sessions** — Sessions survive app restarts via tmux backend
- **Thread history** — Browse all past Claude Code conversations grouped by project, click to resume
- **Import from Terminal.app** — Absorb running Claude Code sessions with one click
- **File preview panel** — Preview files opened by Claude Code in a side-by-side panel
- **Drag & drop** — Drag folders from Finder into the sidebar to create new sessions
- **Usage tracking** — See your Claude API session and weekly usage at a glance
- **Auto-titling** — Sessions get descriptive titles based on what you're working on

## Requirements

- macOS 14.0 (Sonoma) or later
- [tmux](https://github.com/tmux/tmux) installed via Homebrew (`brew install tmux`)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI (`claude login` completed)

## Build

```bash
git clone https://github.com/aryamaniyer/claudex.git
cd claudex
swift build
```

## Install

```bash
./bundle.sh
```

This builds a release binary, creates `Claudex.app`, codesigns it, and installs to `/Applications`.

## Usage

1. **Launch** — Open Claudex from `/Applications` or `open /Applications/Claudex.app`
2. **New session** — Cmd+T to pick a folder, or drag a folder from Finder into the sidebar
3. **Switch sessions** — Cmd+Up/Down arrows, Cmd+Shift+[/], or Cmd+1-9
4. **Import sessions** — Cmd+Shift+I to import running Claude Code sessions from Terminal.app
5. **Resume threads** — Click any conversation in the sidebar's thread history
6. **Close session** — Cmd+W

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+T | New session (folder picker, auto-launches Claude) |
| Cmd+W | Close current session |
| Cmd+Up/Down | Previous/next session |
| Cmd+Shift+[/] | Previous/next session |
| Cmd+1-9 | Jump to session by number |
| Cmd+Shift+I | Import from Terminal.app |
| Cmd+Control+S | Toggle sidebar |
| Cmd+Control+P | Toggle preview panel |
| Cmd++/- | Increase/decrease font size |
| Cmd+0 | Reset font size |

## Architecture

```
SwiftUI App
├── Sidebar (sessions + thread history + usage)
├── Terminal (NSViewRepresentable → SwiftTerm → tmux)
└── Preview panel (file viewer)

SessionManager — session CRUD, persistence, font management
TerminalSession — owns LocalProcessTerminalView, tmux lifecycle
ClaudeAuthService — reads OAuth from Keychain, tracks API usage
ClaudeHistoryScanner — indexes ~/.claude/projects/ conversation files
```

Key design: Terminal views are owned by the model layer (`TerminalSession`), not SwiftUI. The `NSViewRepresentable` swaps terminal subviews in/out without destroying running processes.

## Configuration

### Auto-titling (optional)

Set the `OPENROUTER_API_KEY` environment variable to enable LLM-powered session titles:

```bash
export OPENROUTER_API_KEY="your-key-here"
```

Without this, sessions use the directory name as their title.

### tmux

Claudex uses its own tmux socket (`terminalhub`) and config (`~/.config/terminalhub/tmux.conf`) — it won't interfere with your personal tmux setup.

## Tech Stack

- Swift 6 + SwiftUI (macOS 14+)
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) v1.11.2 — terminal emulation
- tmux — session persistence
- Claude Code OAuth API — usage tracking

## License

MIT
