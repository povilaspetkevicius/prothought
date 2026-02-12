package main

import (
	"database/sql"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

const (
	timestampFormat = "2006-01-02T15:04:05"
)

var (
	// Version information (injected by goreleaser)
	version = "dev"
	commit  = "none"
	date    = "unknown"

	dbPath       string
	hashtagRegex = regexp.MustCompile(`#([\w-]+)`)
)

func init() {
	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error getting home directory: %v\n", err)
		os.Exit(1)
	}
	dbPath = filepath.Join(home, ".prothought.db")
}

// Database initialization
func initDB(db *sql.DB) error {
	queries := []string{
		`CREATE TABLE IF NOT EXISTS thoughts (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			timestamp TEXT NOT NULL,
			text TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS markers (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			thought_id INTEGER NOT NULL,
			marker TEXT NOT NULL,
			FOREIGN KEY (thought_id) REFERENCES thoughts(id) ON DELETE CASCADE
		)`,
		`CREATE INDEX IF NOT EXISTS idx_markers_thought_id ON markers(thought_id)`,
		`CREATE INDEX IF NOT EXISTS idx_markers_marker ON markers(marker)`,
	}

	for _, query := range queries {
		if _, err := db.Exec(query); err != nil {
			return fmt.Errorf("init db: %w", err)
		}
	}

	return nil
}

// Extract hashtags from text
func extractHashtags(text string) []string {
	matches := hashtagRegex.FindAllStringSubmatch(text, -1)
	seen := make(map[string]bool)
	var hashtags []string

	for _, match := range matches {
		if len(match) > 1 {
			tag := strings.ToLower(match[1])
			if !seen[tag] {
				seen[tag] = true
				hashtags = append(hashtags, tag)
			}
		}
	}

	return hashtags
}

// Log a thought with hashtags
func logThought(db *sql.DB, text string) error {
	ts := time.Now().Format(timestampFormat)

	result, err := db.Exec("INSERT INTO thoughts (timestamp, text) VALUES (?, ?)", ts, text)
	if err != nil {
		return fmt.Errorf("insert thought: %w", err)
	}

	thoughtID, err := result.LastInsertId()
	if err != nil {
		return fmt.Errorf("get last insert id: %w", err)
	}

	// Extract and save hashtags
	hashtags := extractHashtags(text)
	for _, tag := range hashtags {
		if _, err := db.Exec("INSERT INTO markers (thought_id, marker) VALUES (?, ?)", thoughtID, tag); err != nil {
			return fmt.Errorf("insert marker: %w", err)
		}
	}

	// Print confirmation
	markerInfo := ""
	if len(hashtags) > 0 {
		markerList := make([]string, len(hashtags))
		for i, tag := range hashtags {
			markerList[i] = "#" + tag
		}
		markerInfo = " with markers: " + strings.Join(markerList, ", ")
	}
	fmt.Printf("Saved thought at %s%s\n", ts, markerInfo)

	return nil
}

// Parse period arguments
func parsePeriod(args []string) (string, string, error) {
	today := time.Now()
	var startDate, endDate time.Time

	key := "today"
	if len(args) > 0 {
		key = args[0]
	}

	switch key {
	case "today":
		startDate = today
		endDate = today
	case "yesterday":
		startDate = today.AddDate(0, 0, -1)
		endDate = startDate
	case "lastweek", "last_week":
		startDate = today.AddDate(0, 0, -6)
		endDate = today
	case "lastmonth", "last_month":
		startDate = today.AddDate(0, 0, -29)
		endDate = today
	default:
		// Try to parse as ISO date
		parsedDate, err := time.Parse("2006-01-02", key)
		if err != nil {
			return "", "", fmt.Errorf("unsupported time period: %s", key)
		}
		startDate = parsedDate
		endDate = parsedDate
	}

	startTime := time.Date(startDate.Year(), startDate.Month(), startDate.Day(), 0, 0, 0, 0, time.Local)
	endTime := time.Date(endDate.Year(), endDate.Month(), endDate.Day(), 23, 59, 59, 0, time.Local)

	return startTime.Format(timestampFormat), endTime.Format(timestampFormat), nil
}

// Thought represents a thought record
type Thought struct {
	Timestamp string
	Text      string
}

// Get thoughts for a period with optional marker filter
func thoughtsForPeriod(db *sql.DB, periodArgs []string, marker string) ([]Thought, error) {
	startTS, endTS, err := parsePeriod(periodArgs)
	if err != nil {
		return nil, err
	}

	var rows *sql.Rows
	if marker != "" {
		// Filter by marker
		rows, err = db.Query(`
			SELECT DISTINCT t.timestamp, t.text
			FROM thoughts t
			INNER JOIN markers m ON t.id = m.thought_id
			WHERE t.timestamp BETWEEN ? AND ?
			  AND m.marker = ?
			ORDER BY t.timestamp ASC`,
			startTS, endTS, strings.ToLower(marker))
	} else {
		rows, err = db.Query(`
			SELECT timestamp, text
			FROM thoughts
			WHERE timestamp BETWEEN ? AND ?
			ORDER BY timestamp ASC`,
			startTS, endTS)
	}

	if err != nil {
		return nil, fmt.Errorf("query thoughts: %w", err)
	}
	defer rows.Close()

	var thoughts []Thought
	for rows.Next() {
		var t Thought
		if err := rows.Scan(&t.Timestamp, &t.Text); err != nil {
			return nil, fmt.Errorf("scan thought: %w", err)
		}
		thoughts = append(thoughts, t)
	}

	return thoughts, rows.Err()
}

// List thoughts for a period
func listThoughts(db *sql.DB, periodArgs []string, marker string) error {
	thoughts, err := thoughtsForPeriod(db, periodArgs, marker)
	if err != nil {
		return err
	}

	if len(thoughts) == 0 {
		markerMsg := ""
		if marker != "" {
			markerMsg = fmt.Sprintf(" with marker #%s", marker)
		}
		fmt.Printf("No thoughts found for that period%s.\n", markerMsg)
		return nil
	}

	for _, t := range thoughts {
		fmt.Printf("[%s] %s\n", t.Timestamp, t.Text)
	}

	return nil
}

// Strike through the last thought
func strikeLastThought(db *sql.DB) error {
	var id int64
	var ts, text string

	err := db.QueryRow(`
		SELECT id, timestamp, text
		FROM thoughts
		ORDER BY timestamp DESC, id DESC
		LIMIT 1`).Scan(&id, &ts, &text)

	if err == sql.ErrNoRows {
		fmt.Println("No thoughts to strike through.")
		return nil
	}
	if err != nil {
		return fmt.Errorf("query last thought: %w", err)
	}

	// Check if already struck through
	if strings.HasPrefix(text, "~~") && strings.HasSuffix(text, "~~") {
		fmt.Println("Last thought is already marked as nvm.")
		return nil
	}

	newText := "~~" + text + "~~"
	if _, err := db.Exec("UPDATE thoughts SET text = ? WHERE id = ?", newText, id); err != nil {
		return fmt.Errorf("update thought: %w", err)
	}

	fmt.Printf("Marked last thought from %s as nvm.\n", ts)
	return nil
}


// Parse arguments with marker
func parseArgsWithMarker(args []string) ([]string, string) {
	var periodArgs []string
	var marker string

	for _, arg := range args {
		if strings.HasPrefix(arg, "#") {
			marker = strings.TrimPrefix(arg, "#")
		} else {
			periodArgs = append(periodArgs, arg)
		}
	}

	return periodArgs, marker
}

// Copy a file from src to dst
func copyFile(src, dst string) error {
	sourceFile, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("open source file: %w", err)
	}
	defer sourceFile.Close()

	destFile, err := os.Create(dst)
	if err != nil {
		return fmt.Errorf("create destination file: %w", err)
	}
	defer destFile.Close()

	if _, err := io.Copy(destFile, sourceFile); err != nil {
		return fmt.Errorf("copy file: %w", err)
	}

	return nil
}

// Copy skills from .agents/skills to ~/.claude/skills
func initSkills() error {
	// Get current working directory
	cwd, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("get working directory: %w", err)
	}

	// Check if .agents/skills exists
	agentsSkillsDir := filepath.Join(cwd, ".agents", "skills")
	if _, err := os.Stat(agentsSkillsDir); os.IsNotExist(err) {
		return fmt.Errorf("no .agents/skills directory found in current directory")
	}

	// Get user's home directory
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("get home directory: %w", err)
	}

	// Target directory
	claudeSkillsDir := filepath.Join(home, ".claude", "skills")

	// Ensure ~/.claude/skills exists
	if err := os.MkdirAll(claudeSkillsDir, 0755); err != nil {
		return fmt.Errorf("create claude skills directory: %w", err)
	}

	// Read all skill directories
	entries, err := os.ReadDir(agentsSkillsDir)
	if err != nil {
		return fmt.Errorf("read skills directory: %w", err)
	}

	copiedCount := 0
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		skillName := entry.Name()
		srcSkillDir := filepath.Join(agentsSkillsDir, skillName)
		dstSkillDir := filepath.Join(claudeSkillsDir, skillName)

		// Create destination skill directory
		if err := os.MkdirAll(dstSkillDir, 0755); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: could not create directory for skill '%s': %v\n", skillName, err)
			continue
		}

		// Copy all files in the skill directory
		skillFiles, err := os.ReadDir(srcSkillDir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: could not read skill '%s': %v\n", skillName, err)
			continue
		}

		for _, file := range skillFiles {
			if file.IsDir() {
				continue
			}

			srcFile := filepath.Join(srcSkillDir, file.Name())
			dstFile := filepath.Join(dstSkillDir, file.Name())

			if err := copyFile(srcFile, dstFile); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: could not copy %s: %v\n", file.Name(), err)
				continue
			}
		}

		fmt.Printf("✓ Copied skill: %s\n", skillName)
		copiedCount++
	}

	if copiedCount == 0 {
		return fmt.Errorf("no skills found to copy")
	}

	fmt.Printf("\nSuccessfully copied %d skill(s) to %s\n", copiedCount, claudeSkillsDir)
	return nil
}

func printUsage() {
	fmt.Fprintf(os.Stderr, `Usage:
  prothought <thought text...>
  prothought nvm
  prothought summarise [today|yesterday|lastweek|lastmonth|YYYY-MM-DD] [#marker]
  prothought summarize [today|yesterday|lastweek|lastmonth|YYYY-MM-DD] [#marker]
  prothought init-skills
  prothought --version

Examples:
  prothought Working on the new feature #work #project
  prothought summarize today #work
  prothought summarize lastweek #personal
  prothought init-skills
`)
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	// Handle version flag
	if os.Args[1] == "--version" || os.Args[1] == "-v" {
		fmt.Printf("prothought version %s (commit: %s, built: %s)\n", version, commit, date)
		return
	}

	// Open database
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error opening database: %v\n", err)
		os.Exit(1)
	}
	defer db.Close()

	// Initialize database
	if err := initDB(db); err != nil {
		fmt.Fprintf(os.Stderr, "Error initializing database: %v\n", err)
		os.Exit(1)
	}

	// Parse command
	cmd := os.Args[1]
	args := os.Args[2:]

	switch cmd {
	case "summarise", "summarize":
		periodArgs, marker := parseArgsWithMarker(args)
		if err := listThoughts(db, periodArgs, marker); err != nil {
			fmt.Fprintf(os.Stderr, "Error listing thoughts: %v\n", err)
			os.Exit(1)
		}

	case "nvm":
		if err := strikeLastThought(db); err != nil {
			fmt.Fprintf(os.Stderr, "Error striking thought: %v\n", err)
			os.Exit(1)
		}

	case "init-skills":
		if err := initSkills(); err != nil {
			fmt.Fprintf(os.Stderr, "Error initializing skills: %v\n", err)
			os.Exit(1)
		}

	default:
		// Log thought (everything as text)
		thoughtText := strings.Join(os.Args[1:], " ")
		thoughtText = strings.TrimSpace(thoughtText)
		if thoughtText == "" {
			printUsage()
			os.Exit(1)
		}

		if err := logThought(db, thoughtText); err != nil {
			fmt.Fprintf(os.Stderr, "Error logging thought: %v\n", err)
			os.Exit(1)
		}
	}
}
