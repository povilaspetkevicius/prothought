## prothought - procrastination thoughts — tiny daily thought logger

**Goal**: a simple CLI you can use every day:

- **Log a thought**: `prothought <thought text...>`
- **See today’s thoughts**: `prothought summarise [today]`

Thoughts are stored locally in a small SQLite database at `~/.prothought.db`.

---

## 1. Requirements

- **Ruby** (recommended: 3.x)
- **Bundler** (for installing gems)
- `sqlite3` Ruby gem (managed via the `Gemfile`)

---

## 2. Running locally from this folder (Ruby)

### 2.1 Install dependencies

From the project directory:

```bash
bundle install
```

This installs the `sqlite3` gem.

### 2.2 Run the CLI

From the project directory:

```bash
ruby prothought.rb "This is my first thought"
ruby prothought.rb summarise today
```

You can use `summarise` or `summarize` (both work).

Supported periods:

- `today` (default if omitted)
- `yesterday`
- `lastweek` (last 7 days including today)
- `lastmonth` (last 30 days including today)
- `YYYY-MM-DD` (ISO date)

Examples (Ruby):

```bash
ruby prothought.rb I feel very focused right now
ruby prothought.rb summarise          # today
ruby prothought.rb summarise today    # today
ruby prothought.rb summarise yesterday
ruby prothought.rb summarise lastweek
ruby prothought.rb summarise lastmonth
ruby prothought.rb summarise 2026-02-05
ruby prothought.rb nvm                # mark last thought as strikethrough (~~text~~)
ruby prothought.rb conclude today     # LLM-powered daily conclusion (Ollama by default)
```

### 2.3 (Optional) LLM configuration (for `conclude`)

By default, `conclude` targets a locally running Ollama server (OpenAI-compatible API) at `http://localhost:11434/v1`.

You can override configuration via environment variables:

- `PROTHOUGHT_LLM_BASE_URL` (default: `http://localhost:11434/v1`)
- `PROTHOUGHT_LLM_MODEL` (optional; if unset, `prothought` will try to auto-pick from `/v1/models`)
- `PROTHOUGHT_LLM_API_KEY` (optional; used for cloud providers, ignored by Ollama)

---

## 3. Making `prothought` a single command (Ruby)

1. **Add a shell alias** (quickest way).

For `zsh`, add this line to your `~/.zshrc`:

```bash
alias prothought="ruby /Users/povilas/src/tries/2026-02-05-day-amplifier/prothought.rb"
```

Then reload your shell config:

```bash
source ~/.zshrc
```

Now you can run:

```bash
prothought This is logged as a thought
prothought summarise today
```

3. **(Optional) Put it directly on your PATH**.

If you prefer, you can copy or symlink the script into a directory that’s already on your `PATH`, such as `/usr/local/bin`:

```bash
ln -s /Users/povilas/src/tries/2026-02-05-day-amplifier/prothought.rb /usr/local/bin/prothought
chmod +x /usr/local/bin/prothought
```

Then you can call `prothought` without the alias.

> Note: you may need `sudo` for writing to `/usr/local/bin` depending on your setup.

---

## 4. Data location and format

- Database file: `~/.prothought.db`
- Schema:
  - `thoughts(id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, text TEXT)`
- Timestamps are stored in ISO8601 format with seconds precision, e.g. `2026-02-05T14:23:01`.

If you ever want to inspect or back up your data, you can copy or open `~/.prothought.db` with any SQLite viewer.

## 5. Example of usage:
```sh
povilas@povilas 2026-02-05-day-amplifier % prothought need to fix rapala waders but maybe i should just buy new waders?
Saved thought at 2026-02-05T16:03:41
povilas@povilas 2026-02-05-day-amplifier % prothought chatgpt told me to not fix these waders so I probably need new waders and wader shoes             
Saved thought at 2026-02-05T16:04:17
povilas@povilas 2026-02-05-day-amplifier % prothought goto museline shop and chat with ernestas and also enroll to his school to get the basics
Saved thought at 2026-02-05T16:04:57
povilas@povilas 2026-02-05-day-amplifier % prothought maybe I should just do everything on my own
Saved thought at 2026-02-05T16:11:39
povilas@povilas 2026-02-05-day-amplifier % prothought nvm
Marked last thought from 2026-02-05T16:11:39 as nvm.
povilas@povilas 2026-02-05-day-amplifier % prothought summarise
[2026-02-05T14:53:54] this is my first thought for today!
[2026-02-05T15:11:32] ~~I just got a briliant idea - I should start hiding taxes~~
[2026-02-05T15:44:43] i am thinking about going to merkys in the middle of April once the ice has been fully moved
[2026-02-05T15:45:15] thinking about whether I should to kayak or packraft
[2026-02-05T16:03:41] need to fix rapala waders but maybe i should just buy new waders?
[2026-02-05T16:04:17] chatgpt told me to not fix these waders so I probably need new waders and wader shoes
[2026-02-05T16:04:57] goto museline shop and chat with ernestas and also enroll to his school to get the basics
[2026-02-05T16:11:39] ~~maybe I should just do everything on my own~~
```
