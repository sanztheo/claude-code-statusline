# bar-status CLI

`bar-status` is an interactive terminal menu (TUI) for configuring the Claude Code statusline without editing JSON files manually.

## Usage

```bash
bar-status
```

## Interface

```
┌────────────────── bar-status ──────────────────┐
│  Claude Code Statusline Configurator           │
├────────────────────────────────────────────────-┤
│  ↑↓ select   ←→ modify   Enter save   q quit  │
├────────────────────────────────────────────────-┤
│  ● saved                                       │
├────────────────────────────────────────────────-┤
│  ▶ Display Mode       compact | full | minimal │
│      Layout density                            │
│    Bar Style          blocks                   │
│    5h Usage           ◉ on                     │
│    7d Usage           ◉ on                     │
│    Context            ◉ on                     │
│    Git Info           ◉ on                     │
│    Duration           ◉ on                     │
├────────────────────────────────────────────────-┤
│  Preview:                                      │
│  proj/ · main · Opus · 12m · ctx [...] · 5h .. │
│  ~/.claude/.../barstatus.config.json            │
└────────────────────────────────────────────────-┘
```

## Controls

| Key | Action |
|-----|--------|
| `↑` / `k` | Move selection up |
| `↓` / `j` | Move selection down |
| `←` / `h` | Change value (previous) |
| `→` / `l` | Change value (next) |
| `Enter` | Save and exit |
| `q` | Quit without saving |
| `Ctrl+C` | Interrupt |

## Options

### Display Mode

Controls the overall layout density.

| Value | Description |
|-------|-------------|
| `compact` | Condensed single-line output (default) |
| `full` | Expanded output with more details |
| `minimal` | Bare minimum information |

### Bar Style

Controls how progress bars are rendered.

| Value | Description |
|-------|-------------|
| `blocks` | Block characters: `[████░░░░]` (default) |
| `tqdm` | tqdm-style: `[###----]` |
| `percent_only` | Just the percentage: `73%` |

### Toggle Options

| Option | Description |
|--------|-------------|
| `5h Usage` | Show 5-hour rolling usage bar |
| `7d Usage` | Show 7-day usage bar |
| `Context` | Show context window usage bar |
| `Git Info` | Show git branch and status indicators |
| `Duration` | Show session elapsed time |

## Live Reload

Changes made in `bar-status` are saved to `barstatus.config.json`. The statusline script reads this file on every refresh cycle, so **changes apply immediately** — no need to restart Claude Code.

## Config File

Settings are saved to:

```
~/.claude/utils/claude_monitor_statusline/barstatus.config.json
```

Example:

```json
{
  "version": 1,
  "display_mode": "compact",
  "bar_style": "blocks",
  "show_5h": true,
  "show_7d": true,
  "show_ctx": true,
  "show_git": true,
  "show_duration": true
}
```
