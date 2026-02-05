## prothought — tiny daily thought logger

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
```

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

