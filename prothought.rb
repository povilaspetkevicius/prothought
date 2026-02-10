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

  db.execute <<~SQL
    CREATE TABLE IF NOT EXISTS markers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      thought_id INTEGER NOT NULL,
      marker TEXT NOT NULL,
      FOREIGN KEY (thought_id) REFERENCES thoughts(id) ON DELETE CASCADE
    )
  SQL

  db.execute <<~SQL
    CREATE INDEX IF NOT EXISTS idx_markers_thought_id ON markers(thought_id)
  SQL

  db.execute <<~SQL
    CREATE INDEX IF NOT EXISTS idx_markers_marker ON markers(marker)
  SQL
end

def extract_hashtags(text)
  # Match hashtags: # followed by alphanumeric characters, underscores, or hyphens
  text.scan(/#([\w-]+)/).flatten.map(&:downcase).uniq
end

def log_thought(db, text)
  ts = Time.now.strftime("%Y-%m-%dT%H:%M:%S")
  db.execute(
    "INSERT INTO thoughts (timestamp, text) VALUES (?, ?)",
    [ts, text]
  )

  # Get the ID of the just-inserted thought
  thought_id = db.last_insert_row_id

  # Extract and save hashtags as markers
  hashtags = extract_hashtags(text)
  hashtags.each do |tag|
    db.execute(
      "INSERT INTO markers (thought_id, marker) VALUES (?, ?)",
      [thought_id, tag]
    )
  end

  marker_info = hashtags.empty? ? "" : " with markers: #{hashtags.map { |t| "##{t}" }.join(', ')}"
  puts "Saved thought at #{ts}#{marker_info}"
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

def list_thoughts(db, period_args, marker: nil)
  start_ts, end_ts = parse_period(period_args)

  if marker
    # Filter by marker
    rows = db.execute(
      <<~SQL,
        SELECT DISTINCT t.timestamp, t.text
        FROM thoughts t
        INNER JOIN markers m ON t.id = m.thought_id
        WHERE t.timestamp BETWEEN ? AND ?
          AND m.marker = ?
        ORDER BY t.timestamp ASC
      SQL
      [start_ts, end_ts, marker.downcase]
    )
  else
    rows = db.execute(
      <<~SQL,
        SELECT timestamp, text
        FROM thoughts
        WHERE timestamp BETWEEN ? AND ?
        ORDER BY timestamp ASC
      SQL
      [start_ts, end_ts]
    )
  end

  if rows.empty?
    marker_msg = marker ? " with marker ##{marker}" : ""
    puts "No thoughts found for that period#{marker_msg}."
    return
  end

  rows.each do |ts, text|
    puts "[#{ts}] #{text}"
  end
end

def thoughts_for_period(db, period_args, marker: nil)
  start_ts, end_ts = parse_period(period_args)

  if marker
    # Filter by marker
    db.execute(
      <<~SQL,
        SELECT DISTINCT t.timestamp, t.text
        FROM thoughts t
        INNER JOIN markers m ON t.id = m.thought_id
        WHERE t.timestamp BETWEEN ? AND ?
          AND m.marker = ?
        ORDER BY t.timestamp ASC
      SQL
      [start_ts, end_ts, marker.downcase]
    )
  else
    db.execute(
      <<~SQL,
        SELECT timestamp, text
        FROM thoughts
        WHERE timestamp BETWEEN ? AND ?
        ORDER BY timestamp ASC
      SQL
      [start_ts, end_ts]
    )
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
    model: ENV["PROTHOUGHT_LLM_MODEL"]
  }
end

def llm_build_uri(base_url, endpoint_path)
  base = URI.parse(base_url)
  base_path = (base.path && !base.path.empty?) ? base.path : "/"
  base_path = "/v1" if base_path == "/"
  base_path = base_path.sub(%r{/\z}, "")

  endpoint_path = endpoint_path.start_with?("/") ? endpoint_path : "/#{endpoint_path}"

  uri = base.dup
  uri.path = "#{base_path}#{endpoint_path}"
  uri.query = nil
  uri
end

def llm_http_client(uri)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == "https")
  http
end

def llm_headers(api_key)
  headers = { "Content-Type" => "application/json" }
  # OpenAI-style servers expect an Authorization header; Ollama ignores it if present
  headers["Authorization"] = "Bearer #{api_key}" if api_key && !api_key.empty?
  headers
end

def llm_list_models
  cfg = llm_config
  uri = llm_build_uri(cfg[:base_url], "/models")

  http = llm_http_client(uri)
  req = Net::HTTP::Get.new(uri.request_uri, llm_headers(cfg[:api_key]))
  res = http.request(req)

  return [] unless res.is_a?(Net::HTTPSuccess)

  data = JSON.parse(res.body)
  items = data["data"]
  return [] unless items.is_a?(Array)

  items.map { |m| m["id"] }.compact
rescue
  []
end

def llm_pick_default_model
  models = llm_list_models
  return "llama3" if models.empty?

  # Prefer llama3 variants if available (common default on Ollama)
  models.find { |id| id.start_with?("llama3") } || models.first
end

def llm_model
  cfg = llm_config
  env_model = cfg[:model]
  return env_model if env_model && !env_model.strip.empty?

  llm_pick_default_model
end

def llm_chat_completion(prompt, system_prompt: "You conclude my daily thoughts. Suggest one thing I should think about next.")
  cfg = llm_config

  uri = llm_build_uri(cfg[:base_url], "/chat/completions")
  headers = llm_headers(cfg[:api_key])

  body = {
    model: llm_model,
    messages: [
      { role: "system", content: system_prompt },
      { role: "user", content: prompt }
    ]
  }

  http = llm_http_client(uri)

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

def conclude_period_with_llm(db, period_args, marker: nil)
  rows = thoughts_for_period(db, period_args, marker: marker)

  if rows.empty?
    marker_msg = marker ? " with marker ##{marker}" : ""
    puts "No thoughts found for that period#{marker_msg}."
    return
  end

  prompt = rows.map { |ts, text| "[#{ts}] #{text}" }.join("\n")

  begin
    summary = llm_chat_completion(prompt)
  rescue => e
    $stderr.puts "Error contacting LLM: #{e.message}"
    return
  end

  puts summary
end

def print_usage
  $stderr.puts <<~TXT
    Usage:
      prothought <thought text...>
      prothought nvm
      prothought conclude [today|yesterday|lastweek|lastmonth|YYYY-MM-DD] [#marker]
      prothought summarise [today|yesterday|lastweek|lastmonth|YYYY-MM-DD] [#marker]
      prothought summarize [today|yesterday|lastweek|lastmonth|YYYY-MM-DD] [#marker]

    Examples:
      prothought Working on the new feature #work #project
      prothought conclude today #work
      prothought summarize lastweek #personal
  TXT
end

def parse_args_with_marker(args)
  # Separate marker (starts with #) from other arguments
  marker = nil
  period_args = []

  args.each do |arg|
    if arg.start_with?("#")
      marker = arg[1..] # Remove the # prefix
    else
      period_args << arg
    end
  end

  [period_args, marker]
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
    period_args, marker = parse_args_with_marker(ARGV[1..] || [])
    list_thoughts(db, period_args, marker: marker)
  elsif cmd == "conclude"
    period_args, marker = parse_args_with_marker(ARGV[1..] || [])
    conclude_period_with_llm(db, period_args, marker: marker)
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
