#!/usr/bin/env ruby

require "sqlite3"
require "date"
require "net/http"
require "uri"
require "json"

DB_PATH = File.expand_path("~/.prothought.db")

def init_db(db)
  db.execute <<~SQL
    CREATE TABLE IF NOT EXISTS thoughts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp TEXT NOT NULL,
      text TEXT NOT NULL
    )
  SQL
end

def log_thought(db, text)
  ts = Time.now.strftime("%Y-%m-%dT%H:%M:%S")
  db.execute(
    "INSERT INTO thoughts (timestamp, text) VALUES (?, ?)",
    [ts, text]
  )
  puts "Saved thought at #{ts}"
end

def parse_period(args)
  # Returns [start_ts_string, end_ts_string]
  today = Date.today
  key = (args[0] || "today")

  case key
  when "today"
    start_date = today
    end_date = today
  when "yesterday"
    start_date = today - 1
    end_date = start_date
  when "lastweek", "last_week"
    # Last 7 full days including today
    start_date = today - 6
    end_date = today
  when "lastmonth", "last_month"
    # Last 30 full days including today
    start_date = today - 29
    end_date = today
  else
    begin
      start_date = Date.iso8601(key)
    rescue ArgumentError
      $stderr.puts "Unsupported time period."
      $stderr.puts "Use one of: 'today', 'yesterday', 'lastweek', 'lastmonth', or 'YYYY-MM-DD'."
      exit 1
    end
    end_date = start_date
  end

  start_dt = DateTime.new(start_date.year, start_date.month, start_date.day, 0, 0, 0)
  end_dt = DateTime.new(end_date.year, end_date.month, end_date.day, 23, 59, 59)

  [
    start_dt.strftime("%Y-%m-%dT%H:%M:%S"),
    end_dt.strftime("%Y-%m-%dT%H:%M:%S")
  ]
end

def list_thoughts(db, period_args)
  start_ts, end_ts = parse_period(period_args)

  rows = db.execute(
    <<~SQL,
      SELECT timestamp, text
      FROM thoughts
      WHERE timestamp BETWEEN ? AND ?
      ORDER BY timestamp ASC
    SQL
    [start_ts, end_ts]
  )

  if rows.empty?
    puts "No thoughts found for that period."
    return
  end

  rows.each do |ts, text|
    puts "[#{ts}] #{text}"
  end
end

def strike_last_thought(db)
  row = db.get_first_row(<<~SQL)
    SELECT id, timestamp, text
    FROM thoughts
    ORDER BY timestamp DESC, id DESC
    LIMIT 1
  SQL

  if row.nil?
    puts "No thoughts to strike through."
    return
  end

  id, ts, text = row

  # If already wrapped in Markdown strikethrough, do nothing.
  if text.start_with?("~~") && text.end_with?("~~")
    puts "Last thought is already marked as nvm."
    return
  end

  new_text = "~~#{text}~~"

  db.execute(
    "UPDATE thoughts SET text = ? WHERE id = ?",
    [new_text, id]
  )
  puts "Marked last thought from #{ts} as nvm."
end

# --- Generic OpenAI-compatible LLM client (defaults to local Ollama) ---

def llm_config
  {
    base_url: ENV.fetch("PROTHOUGHT_LLM_BASE_URL", "http://localhost:11434/v1"),
    api_key: ENV["PROTHOUGHT_LLM_API_KEY"], # optional / ignored by Ollama
    model: ENV.fetch("PROTHOUGHT_LLM_MODEL", "llama3")
  }
end

def llm_chat_completion(prompt, system_prompt: "You summarise my daily thoughts.")
  cfg = llm_config

  uri = URI.join(cfg[:base_url], "/chat/completions")

  headers = { "Content-Type" => "application/json" }
  # OpenAI-style servers expect an Authorization header; Ollama ignores it if present
  headers["Authorization"] = "Bearer #{cfg[:api_key]}" if cfg[:api_key] && !cfg[:api_key].empty?

  body = {
    model: cfg[:model],
    messages: [
      { role: "system", content: system_prompt },
      { role: "user", content: prompt }
    ]
  }

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == "https")

  req = Net::HTTP::Post.new(uri.request_uri, headers)
  req.body = JSON.dump(body)

  res = http.request(req)

  unless res.is_a?(Net::HTTPSuccess)
    raise "LLM request failed (#{res.code}): #{res.body}"
  end

  data = JSON.parse(res.body)

  choice = data.fetch("choices", [])[0]
  unless choice && choice["message"] && choice["message"]["content"]
    raise "Unexpected LLM response format: #{res.body}"
  end

  choice["message"]["content"]
end

def print_usage
  $stderr.puts <<~TXT
    Usage:
      prothought <thought text...>
      prothought nvm
      prothought summarise [today|yesterday|lastweek|lastmonth|YYYY-MM-DD]
      prothought summarize [today|yesterday|lastweek|lastmonth|YYYY-MM-DD]
  TXT
end

def main
  if ARGV.empty?
    print_usage
    exit 1
  end

  cmd = ARGV.first

  db = SQLite3::Database.new(DB_PATH)
  init_db(db)

  if %w[summarise summarize].include?(cmd)
    period_args = ARGV[1..] || []
    list_thoughts(db, period_args)
  elsif cmd == "nvm"
    strike_last_thought(db)
  else
    thought_text = ARGV.join(" ").strip
    if thought_text.empty?
      print_usage
      exit 1
    end
    log_thought(db, thought_text)
  end
ensure
  db&.close
end

if __FILE__ == $PROGRAM_NAME
  main
end
