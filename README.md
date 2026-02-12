# Prothought

A simple, fast CLI for logging daily thoughts with hashtag support.

## Features

- 📝 **Log thoughts** instantly from your terminal
- 🏷️ **Hashtag support** for organizing thoughts
- 🔍 **Filter by hashtag** to find related thoughts
- ⚡ **Native binary** - no dependencies required
- 🗄️ **SQLite storage** at `~/.prothought.db`
- 🚫 **Mark as "nvm"** - strike through thoughts you changed your mind about

## Installation

### From Homebrew (once published)

```bash
brew tap povilaspetkevicius/tap
brew install povilaspetkevicius/tap/prothought
```

### From Source

```bash
git clone https://github.com/povilaspetkevicius/prothought
cd prothought
go build -ldflags="-s -w" -o prothought
sudo mv prothought /usr/local/bin/
```

### Download Binary

Get the latest release from [GitHub Releases](https://github.com/povilaspetkevicius/prothought/releases)

## Usage

### Install Skills

`prothought` could be used as a skill addition to your llm. Simply type in 'memorise this thread' in your local llm window, and `memorise` skill will be invoked automatically.
This skill makes llm digest the current thread into 1-2 sentences and write it to your local prothought-memory.

To copy agent skills from this project to your local configuration:

```bash
prothought init-skills
```

This will copy all skills from `.agents/skills/` to `~/.claude/skills/`, making them available in Claude Code. Other llms are yet to be covered.

### Log a Thought

```bash
prothought Working on the authentication feature #work #backend
prothought Had a great idea for improving performance #ideas
```

### View Thoughts

```bash
# Today's thoughts
prothought summarize

# Yesterday
prothought summarize yesterday

# Last 7 days
prothought summarize lastweek

# Last 30 days
prothought summarize lastmonth

# Specific date
prothought summarize 2026-02-05
```

### Filter by Hashtag

```bash
# Show only work-related thoughts
prothought summarize today #work

# Show personal thoughts from last week
prothought summarize lastweek #personal
```

### Strike Through Last Thought

Changed your mind about something? Mark it as "never mind":

```bash
prothought nvm
```

This wraps the last thought in markdown strikethrough (`~~text~~`).

## Database

Thoughts are stored in `~/.prothought.db` (SQLite).

### Schema

**thoughts** table:
- `id` - Auto-incrementing primary key
- `timestamp` - ISO 8601 timestamp (YYYY-MM-DDTHH:MM:SS)
- `text` - The thought text

**markers** table:
- `id` - Auto-incrementing primary key
- `thought_id` - Foreign key to thoughts
- `marker` - The hashtag (without #, lowercase)

## Hashtags

Hashtags are automatically extracted from your thoughts and stored as markers:

- **Format**: `#word`, `#work-project`, `#test_case`
- **Case-insensitive**: `#Work` and `#work` are the same
- **Multiple tags**: Use as many as you want per thought
- **Filtering**: Filter thoughts by any hashtag when viewing

## Examples

```bash
# Install skills to Claude Code
$ prothought init-skills
✓ Copied skill: memorise

Successfully copied 1 skill(s) to /Users/username/.claude/skills

# Log thoughts with hashtags
$ prothought Fixed the login bug #work #bugfix
Saved thought at 2026-02-10T15:30:42 with markers: #work, #bugfix

$ prothought Need to buy new fishing waders #personal #shopping
Saved thought at 2026-02-10T15:31:15 with markers: #personal, #shopping

$ prothought Actually, I'll fix the old ones #personal
Saved thought at 2026-02-10T15:31:45 with markers: #personal

$ prothought nvm
Marked last thought from 2026-02-10T15:31:45 as nvm.

# View all today's thoughts
$ prothought summarize
[2026-02-10T15:30:42] Fixed the login bug #work #bugfix
[2026-02-10T15:31:15] Need to buy new fishing waders #personal #shopping
[2026-02-10T15:31:45] ~~Actually, I'll fix the old ones #personal~~

# View only work-related thoughts
$ prothought summarize today #work
[2026-02-10T15:30:42] Fixed the login bug #work #bugfix
```

## Development

### Build

```bash
go build -o prothought main.go
```

### Build with Optimizations

```bash
go build -ldflags="-s -w" -o prothought main.go
```

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR.