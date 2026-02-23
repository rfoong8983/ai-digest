# Weekly Best-Of Digest Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a weekly "best of" digest that curates the top 5 items from the past week's daily digests using Claude Sonnet, posts to Slack, and saves locally.

**Architecture:** A new `WeeklyCurator` class reads saved daily markdown digests, parses out items, sends them to Claude Sonnet via Bedrock for themed curation, and returns structured results. A separate `bin/weekly-digest` orchestrator and `bin/run-weekly-digest.sh` wrapper mirror the daily pattern. The `bin/install` script gains a `--weekly` flag to set up a Monday 10 AM launchd job.

**Tech Stack:** Ruby 3.4, minitest, webmock, aws-sdk-bedrockruntime, same Slack webhook as daily.

---

### Task 1: Add Weekly Config to settings.yml

**Files:**
- Modify: `config/settings.yml`

**Step 1: Add weekly section to config**

Add to the end of `config/settings.yml`:

```yaml
weekly:
  model_id: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  max_items: 5
  lookback_days: 7
```

**Step 2: Commit**

```bash
git add config/settings.yml
git commit -m "feat: add weekly digest config section"
```

---

### Task 2: WeeklyCurator — Markdown Parser

**Files:**
- Create: `lib/ai_digest/weekly_curator.rb`
- Create: `test/weekly_curator_test.rb`
- Modify: `lib/ai_digest.rb` (add require)

The `WeeklyCurator` needs to read daily digest `.md` files and extract structured items. The daily markdown format (from `Storage.format_markdown`) looks like:

```markdown
# AI Digest — February 23, 2026

## 1. Article Title

**Source:** Source Name | **Tags:** `tag1` `tag2`

Summary text here.

[Read more](https://example.com/url)

---

## 2. Another Article
...
```

**Step 1: Write the failing tests for markdown parsing**

Create `test/weekly_curator_test.rb`:

```ruby
require_relative "test_helper"
require "json"
require "tmpdir"
require "fileutils"

class WeeklyCuratorTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("ai-digest-weekly-test")
    @config = {
      "topics" => ["AI coding agents and assistants"],
      "weekly" => {
        "model_id" => "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
        "max_items" => 5,
        "lookback_days" => 7
      },
      "bedrock" => { "region" => "us-east-1" },
      "storage" => { "path" => @tmpdir }
    }
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_parse_daily_digest_extracts_items
    markdown = <<~MD
      # AI Digest — February 23, 2026

      ## 1. Agentic Engineering Patterns

      **Source:** Simon Willison | **Tags:** `coding-agent` `dev-tooling`

      Simon documents best practices for AI coding agents.

      [Read more](https://example.com/patterns)

      ---

      ## 2. Claude C Compiler

      **Source:** Anthropic Blog | **Tags:** `model-capabilities`

      Anthropic builds a C compiler with Claude.

      [Read more](https://example.com/compiler)
    MD

    items = AiDigest::WeeklyCurator.parse_daily_digest(markdown)

    assert_equal 2, items.length
    assert_equal "Agentic Engineering Patterns", items[0]["title"]
    assert_equal "Simon Willison", items[0]["source"]
    assert_equal ["coding-agent", "dev-tooling"], items[0]["tags"]
    assert_includes items[0]["summary"], "best practices"
    assert_equal "https://example.com/patterns", items[0]["url"]
    assert_equal "Claude C Compiler", items[1]["title"]
  end

  def test_parse_daily_digest_handles_empty_digest
    markdown = "# AI Digest — February 23, 2026\n\nNo relevant AI news found today.\n"
    items = AiDigest::WeeklyCurator.parse_daily_digest(markdown)
    assert_equal [], items
  end

  def test_load_week_reads_daily_files
    # Write two daily files in the digests dir
    File.write(File.join(@tmpdir, "#{Date.today.strftime('%Y-%m-%d')}.md"), <<~MD)
      # AI Digest — #{Date.today.strftime('%B %d, %Y')}

      ## 1. Today Article

      **Source:** Test Blog | **Tags:** `test`

      A summary.

      [Read more](https://example.com/today)
    MD

    yesterday = Date.today - 1
    File.write(File.join(@tmpdir, "#{yesterday.strftime('%Y-%m-%d')}.md"), <<~MD)
      # AI Digest — #{yesterday.strftime('%B %d, %Y')}

      ## 1. Yesterday Article

      **Source:** Other Blog | **Tags:** `other`

      Another summary.

      [Read more](https://example.com/yesterday)
    MD

    items = AiDigest::WeeklyCurator.load_week(@config)

    assert_equal 2, items.length
    titles = items.map { |i| i["title"] }
    assert_includes titles, "Today Article"
    assert_includes titles, "Yesterday Article"
  end

  def test_load_week_skips_weekly_files
    File.write(File.join(@tmpdir, "weekly-#{Date.today.strftime('%Y-%m-%d')}.md"), "# Weekly\n\nstuff")
    File.write(File.join(@tmpdir, "#{Date.today.strftime('%Y-%m-%d')}.md"), <<~MD)
      # AI Digest — #{Date.today.strftime('%B %d, %Y')}

      ## 1. Daily Article

      **Source:** Blog | **Tags:** `tag`

      Summary.

      [Read more](https://example.com/daily)
    MD

    items = AiDigest::WeeklyCurator.load_week(@config)

    assert_equal 1, items.length
    assert_equal "Daily Article", items[0]["title"]
  end

  def test_load_week_ignores_files_outside_lookback
    old_date = Date.today - 10
    File.write(File.join(@tmpdir, "#{old_date.strftime('%Y-%m-%d')}.md"), <<~MD)
      # AI Digest — #{old_date.strftime('%B %d, %Y')}

      ## 1. Old Article

      **Source:** Blog | **Tags:** `tag`

      Summary.

      [Read more](https://example.com/old)
    MD

    items = AiDigest::WeeklyCurator.load_week(@config)
    assert_equal [], items
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Ilib:test test/weekly_curator_test.rb`
Expected: NameError — `AiDigest::WeeklyCurator` not defined

**Step 3: Create the WeeklyCurator with markdown parser and load_week**

Create `lib/ai_digest/weekly_curator.rb`:

```ruby
require "date"

module AiDigest
  class WeeklyCurator
    def self.parse_daily_digest(markdown)
      items = []
      # Split on the item headers (## N. Title)
      sections = markdown.split(/^## \d+\.\s+/)
      sections.shift # discard everything before first item

      sections.each do |section|
        lines = section.strip.split("\n").map(&:strip).reject(&:empty?)
        next if lines.empty?

        title = lines[0]

        source = nil
        tags = []
        summary_lines = []
        url = nil

        lines[1..].each do |line|
          if line.start_with?("**Source:**")
            match = line.match(/\*\*Source:\*\*\s*(.+?)\s*\|\s*\*\*Tags:\*\*\s*(.+)/)
            if match
              source = match[1].strip
              tags = match[2].scan(/`([^`]+)`/).flatten
            end
          elsif line.match?(/^\[Read more\]\((.+)\)$/)
            url = line.match(/^\[Read more\]\((.+)\)$/)[1]
          elsif !line.start_with?("---")
            summary_lines << line
          end
        end

        next unless title && url

        items << {
          "title" => title,
          "source" => source,
          "tags" => tags,
          "summary" => summary_lines.join(" "),
          "url" => url
        }
      end

      items
    end

    def self.load_week(config)
      digests_path = File.join(AiDigest.root, config.dig("storage", "path") || "digests")
      lookback = config.dig("weekly", "lookback_days") || 7
      cutoff = Date.today - lookback

      items = []
      Dir.glob(File.join(digests_path, "*.md")).each do |file|
        basename = File.basename(file, ".md")
        # Skip weekly digest files
        next if basename.start_with?("weekly-")
        # Parse date from filename
        begin
          file_date = Date.parse(basename)
        rescue Date::Error
          next
        end
        next if file_date < cutoff

        markdown = File.read(file)
        file_items = parse_daily_digest(markdown)
        file_items.each { |item| item["date"] = file_date.to_s }
        items.concat(file_items)
      end

      items
    end
  end
end
```

**Step 4: Add require to lib/ai_digest.rb**

Add `require_relative "ai_digest/weekly_curator"` at the end of `lib/ai_digest.rb`, after the `storage` require.

**Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Ilib:test test/weekly_curator_test.rb`
Expected: 5 tests, 0 failures

**Step 6: Run all tests to verify no regressions**

Run: `bundle exec ruby -Ilib:test -e "Dir.glob('test/**/*_test.rb').each { |f| require File.expand_path(f) }"`
Expected: All pass

**Step 7: Commit**

```bash
git add lib/ai_digest/weekly_curator.rb test/weekly_curator_test.rb lib/ai_digest.rb
git commit -m "feat: add WeeklyCurator with markdown parser and load_week"
```

---

### Task 3: WeeklyCurator — Prompt Builder and Response Parser

**Files:**
- Modify: `lib/ai_digest/weekly_curator.rb`
- Modify: `test/weekly_curator_test.rb`

**Step 1: Write failing tests for build_prompt and parse_response**

Add to `test/weekly_curator_test.rb`:

```ruby
def test_build_prompt_includes_items_and_config
  items = [
    { "title" => "Article A", "source" => "Blog A", "summary" => "Summary A", "tags" => ["agent"], "url" => "https://a.com", "date" => "2026-02-23" },
    { "title" => "Article B", "source" => "Blog B", "summary" => "Summary B", "tags" => ["model"], "url" => "https://b.com", "date" => "2026-02-22" }
  ]

  prompt = AiDigest::WeeklyCurator.build_prompt(items, @config)

  assert_includes prompt, "Article A"
  assert_includes prompt, "Article B"
  assert_includes prompt, "5"  # max_items
  assert_includes prompt, "themes"
  assert_includes prompt, "why_it_matters"
end

def test_parse_response_extracts_themed_items
  response_text = <<~JSON
    {
      "themes": [
        {
          "theme": "Agentic Engineering",
          "items": [
            {
              "title": "Agentic Patterns",
              "source": "Simon Willison",
              "why_it_matters": "Defines best practices for AI-assisted development.",
              "url": "https://example.com/patterns"
            }
          ]
        }
      ]
    }
  JSON

  result = AiDigest::WeeklyCurator.parse_response(response_text)

  assert_equal 1, result["themes"].length
  assert_equal "Agentic Engineering", result["themes"][0]["theme"]
  assert_equal 1, result["themes"][0]["items"].length
  assert_equal "Agentic Patterns", result["themes"][0]["items"][0]["title"]
end

def test_parse_response_handles_malformed_json
  result = AiDigest::WeeklyCurator.parse_response("not json")
  assert_equal({ "themes" => [] }, result)
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Ilib:test test/weekly_curator_test.rb`
Expected: NoMethodError — `build_prompt` and `parse_response` not defined

**Step 3: Implement build_prompt and parse_response**

Add to `lib/ai_digest/weekly_curator.rb` inside the class:

```ruby
def self.build_prompt(items, config)
  topics = config["topics"].map { |t| "- #{t}" }.join("\n")
  max_items = config.dig("weekly", "max_items") || 5

  items_text = items.map.with_index(1) do |item, i|
    date = item["date"] || "unknown"
    tags = Array(item["tags"]).join(", ")
    "#{i}. [#{date}] [#{item['source']}] #{item['title']}\n   Tags: #{tags}\n   Summary: #{item['summary']}\n   URL: #{item['url']}"
  end.join("\n\n")

  <<~PROMPT
    You are an AI news curator creating a weekly "best of" digest. Below are all items from this week's daily digests.

    Your job:
    1. Identify the #{max_items} most significant developments from the week
    2. Group them by theme (2-3 themes)
    3. If the same topic appeared multiple days or from multiple sources, that signals higher significance
    4. For each item, explain why it matters this week

    Focus on these topics:
    #{topics}

    Return a JSON object with this structure:
    {
      "themes": [
        {
          "theme": "Theme Name",
          "items": [
            {
              "title": "Item title",
              "source": "Source name",
              "why_it_matters": "2-3 sentences on why this is significant this week",
              "url": "https://..."
            }
          ]
        }
      ]
    }

    Total items across all themes must be at most #{max_items}.
    Return ONLY valid JSON — no markdown fences, no extra text.

    This week's items:
    #{items_text}
  PROMPT
end

def self.call_bedrock(prompt, config)
  client = Aws::BedrockRuntime::Client.new(
    region: config.dig("bedrock", "region")
  )

  response = client.converse(
    model_id: config.dig("weekly", "model_id"),
    messages: [
      { role: "user", content: [{ text: prompt }] }
    ],
    inference_config: { max_tokens: 4096 }
  )

  response.output.message.content.first.text
end

def self.parse_response(text)
  cleaned = text.gsub(/\A```json\s*/, "").gsub(/\s*```\z/, "").strip
  JSON.parse(cleaned)
rescue JSON::ParserError => e
  warn "Failed to parse weekly curator response: #{e.message}"
  { "themes" => [] }
end

def self.curate(config)
  items = load_week(config)
  return { "themes" => [] } if items.empty?

  prompt = build_prompt(items, config)
  response_text = call_bedrock(prompt, config)
  parse_response(response_text)
end
```

Add `require "aws-sdk-bedrockruntime"` and `require "json"` at the top of the file.

**Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Ilib:test test/weekly_curator_test.rb`
Expected: 8 tests, 0 failures

**Step 5: Commit**

```bash
git add lib/ai_digest/weekly_curator.rb test/weekly_curator_test.rb
git commit -m "feat: add WeeklyCurator prompt builder, Bedrock caller, and response parser"
```

---

### Task 4: Weekly Slack Formatting and Storage

**Files:**
- Modify: `lib/ai_digest/slack_poster.rb`
- Modify: `lib/ai_digest/storage.rb`
- Modify: `test/slack_poster_test.rb`
- Modify: `test/storage_test.rb`

The weekly digest uses a themed structure (`{ "themes" => [...] }`) instead of a flat array. SlackPoster and Storage need methods to format this.

**Step 1: Write failing tests**

Add to `test/slack_poster_test.rb`:

```ruby
def test_format_weekly_message_includes_themes
  weekly_result = {
    "themes" => [
      {
        "theme" => "Agentic Engineering",
        "items" => [
          {
            "title" => "Agentic Patterns",
            "source" => "Simon Willison",
            "why_it_matters" => "Defines best practices.",
            "url" => "https://example.com/patterns"
          }
        ]
      }
    ]
  }

  message = AiDigest::SlackPoster.format_weekly_message(weekly_result, Date.today - 6, Date.today)

  assert_includes message, "Weekly Best of AI"
  assert_includes message, "Agentic Engineering"
  assert_includes message, "Agentic Patterns"
  assert_includes message, "Defines best practices."
end

def test_format_weekly_message_handles_empty_themes
  message = AiDigest::SlackPoster.format_weekly_message({ "themes" => [] }, Date.today - 6, Date.today)
  assert_includes message, "No notable items"
end
```

Add to `test/storage_test.rb`:

```ruby
def test_save_weekly_creates_prefixed_file
  weekly_result = {
    "themes" => [
      {
        "theme" => "Test Theme",
        "items" => [
          {
            "title" => "Test Article",
            "source" => "Blog",
            "why_it_matters" => "It matters.",
            "url" => "https://example.com"
          }
        ]
      }
    ]
  }

  AiDigest::Storage.save_weekly(weekly_result, Date.today - 6, Date.today, path: @tmpdir)

  expected_file = File.join(@tmpdir, "weekly-#{Date.today.strftime('%Y-%m-%d')}.md")
  assert File.exist?(expected_file)

  content = File.read(expected_file)
  assert_includes content, "Weekly Best of AI"
  assert_includes content, "Test Theme"
  assert_includes content, "Test Article"
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Ilib:test test/slack_poster_test.rb test/storage_test.rb`
Expected: NoMethodError for `format_weekly_message` and `save_weekly`

**Step 3: Implement format_weekly_message in SlackPoster**

Add to `lib/ai_digest/slack_poster.rb` inside the class:

```ruby
def self.post_weekly(weekly_result, start_date, end_date)
  webhook_url = AiDigest.config.dig("slack", "webhook_url") || ENV["AI_DIGEST_SLACK_WEBHOOK"]
  unless webhook_url
    warn "Slack webhook not configured"
    return false
  end

  message = format_weekly_message(weekly_result, start_date, end_date)
  uri = URI(webhook_url)
  response = Net::HTTP.post(uri, JSON.generate({ text: message }), "Content-Type" => "application/json")
  response.is_a?(Net::HTTPSuccess)
rescue StandardError => e
  warn "Error posting to Slack: #{e.message}"
  false
end

def self.format_weekly_message(weekly_result, start_date, end_date)
  date_range = "#{start_date.strftime('%b %d')}-#{end_date.strftime('%d, %Y')}"
  themes = weekly_result["themes"]

  if themes.nil? || themes.empty?
    return "Weekly Best of AI — #{date_range}\n\nNo notable items this week."
  end

  counter = 0
  themes_text = themes.map do |theme|
    items_text = theme["items"].map do |item|
      counter += 1
      [
        "#{counter}. *#{item['title']}*",
        "   Source: #{item['source']}",
        "   #{item['why_it_matters']}",
        "   #{item['url']}"
      ].join("\n")
    end.join("\n\n")
    "*Theme: #{theme['theme']}*\n\n#{items_text}"
  end.join("\n\n")

  "Weekly Best of AI — #{date_range}\n\n#{themes_text}"
end
```

**Step 4: Implement save_weekly in Storage**

Add to `lib/ai_digest/storage.rb` inside the class:

```ruby
def self.save_weekly(weekly_result, start_date, end_date, path: nil)
  path ||= File.join(AiDigest.root, AiDigest.config.dig("storage", "path") || "digests")
  FileUtils.mkdir_p(path)

  filename = "weekly-#{end_date.strftime('%Y-%m-%d')}.md"
  filepath = File.join(path, filename)

  content = format_weekly_markdown(weekly_result, start_date, end_date)
  File.write(filepath, content)

  filepath
end

def self.format_weekly_markdown(weekly_result, start_date, end_date)
  date_range = "#{start_date.strftime('%B %d')} - #{end_date.strftime('%B %d, %Y')}"
  themes = weekly_result["themes"]

  if themes.nil? || themes.empty?
    return "# Weekly Best of AI — #{date_range}\n\nNo notable items this week.\n"
  end

  counter = 0
  themes_md = themes.map do |theme|
    items_md = theme["items"].map do |item|
      counter += 1
      [
        "### #{counter}. #{item['title']}",
        "",
        "**Source:** #{item['source']}",
        "",
        item["why_it_matters"],
        "",
        "[Read more](#{item['url']})"
      ].join("\n")
    end.join("\n\n")
    "## #{theme['theme']}\n\n#{items_md}"
  end.join("\n\n---\n\n")

  "# Weekly Best of AI — #{date_range}\n\n#{themes_md}\n"
end
```

**Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Ilib:test test/slack_poster_test.rb test/storage_test.rb`
Expected: All pass

**Step 6: Run all tests**

Run: `bundle exec ruby -Ilib:test -e "Dir.glob('test/**/*_test.rb').each { |f| require File.expand_path(f) }"`
Expected: All pass

**Step 7: Commit**

```bash
git add lib/ai_digest/slack_poster.rb lib/ai_digest/storage.rb test/slack_poster_test.rb test/storage_test.rb
git commit -m "feat: add weekly Slack formatting and weekly markdown storage"
```

---

### Task 5: Weekly Orchestrator and Wrapper Script

**Files:**
- Create: `bin/weekly-digest`
- Create: `bin/run-weekly-digest.sh`

**Step 1: Create bin/weekly-digest**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

$stdout.sync = true
$stderr.sync = true

require_relative "../lib/ai_digest"

lookback = AiDigest.config.dig("weekly", "lookback_days") || 7
end_date = Date.today
start_date = end_date - lookback + 1

puts "Weekly Best of AI — #{start_date.strftime('%b %d')} to #{end_date.strftime('%b %d, %Y')}"
puts "=" * 40

# 1. Load daily digests
puts "\nLoading daily digests from the last #{lookback} days..."
items = AiDigest::WeeklyCurator.load_week(AiDigest.config)
puts "Found #{items.length} items across daily digests."

if items.empty?
  puts "No items found. Exiting."
  exit 0
end

# 2. Curate via Sonnet
puts "\nCurating top items via Claude Sonnet..."
weekly_result = AiDigest::WeeklyCurator.curate(AiDigest.config)
total = weekly_result["themes"].sum { |t| t["items"].length }
puts "Selected #{total} items across #{weekly_result['themes'].length} themes."

# 3. Post to Slack
puts "\nPosting to Slack..."
if AiDigest::SlackPoster.post_weekly(weekly_result, start_date, end_date)
  puts "Posted to Slack successfully."
else
  puts "Slack post skipped or failed."
end

# 4. Save locally
filepath = AiDigest::Storage.save_weekly(weekly_result, start_date, end_date)
puts "Saved digest to #{filepath}"

puts "\nDone!"
```

**Step 2: Make it executable**

```bash
chmod +x bin/weekly-digest
```

**Step 3: Create bin/run-weekly-digest.sh**

```bash
#!/bin/bash
export LANG=en_US.UTF-8

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

exec >> "$PROJECT_DIR/weekly-digest.log" 2>&1
echo "=== $(date) ==="
cd "$PROJECT_DIR"
bundle exec ruby bin/weekly-digest
echo "Exit code: $?"
```

**Step 4: Make it executable**

```bash
chmod +x bin/run-weekly-digest.sh
```

**Step 5: Commit**

```bash
git add bin/weekly-digest bin/run-weekly-digest.sh
git commit -m "feat: add weekly digest orchestrator and launchd wrapper"
```

---

### Task 6: Update Install Script with --weekly Flag

**Files:**
- Modify: `bin/install`
- Modify: `.gitignore`

**Step 1: Update bin/install to support --weekly**

Refactor `bin/install` to handle a `--weekly` flag. When passed, it installs the weekly job (`com.ai-digest.weekly`) pointing to `bin/run-weekly-digest.sh` with a `StartCalendarInterval` that includes `Weekday = 1` (Monday). The time argument still works.

The key changes:
- Parse `--weekly` from ARGV before the time argument
- Use different label, wrapper path, log path, and plist schedule depending on mode
- Weekly schedule adds `<key>Weekday</key><integer>1</integer>` to the `StartCalendarInterval`

The full updated `bin/install`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates and installs launchd plist(s) with paths derived from the current environment.
#
# Usage:
#   ruby bin/install              # daily job, defaults to 10:00 AM
#   ruby bin/install 8:30         # daily job at 8:30 AM
#   ruby bin/install --weekly     # weekly job, Monday 10:00 AM
#   ruby bin/install --weekly 9:00  # weekly job, Monday 9:00 AM

require "fileutils"

weekly = ARGV.delete("--weekly")
label = weekly ? "com.ai-digest.weekly" : "com.ai-digest"

# Parse time argument
hour, minute = 10, 0
time_arg = ARGV[0]
if time_arg
  parts = time_arg.split(":")
  hour = Integer(parts[0])
  minute = Integer(parts[1] || 0)
  unless (0..23).include?(hour) && (0..59).include?(minute)
    abort "Invalid time: #{time_arg} (expected HH:MM in 24-hour format)"
  end
end

project_dir = File.expand_path("..", __dir__)
home_dir    = ENV.fetch("HOME")
wrapper     = File.join(project_dir, "bin", weekly ? "run-weekly-digest.sh" : "run-digest.sh")
plist_dest  = File.join(home_dir, "Library", "LaunchAgents", "#{label}.plist")

# Detect ruby version manager shims
rbenv_shims = "/opt/homebrew/opt/rbenv/shims"
mise_shims  = File.join(home_dir, ".mise", "shims")

shim_path = if Dir.exist?(rbenv_shims) && system("which rbenv > /dev/null 2>&1")
              rbenv_shims
            elsif Dir.exist?(mise_shims)
              mise_shims
            else
              nil
            end

path_components = [shim_path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].compact
path_value = path_components.join(":")

weekday_entry = weekly ? "\n          <key>Weekday</key>\n          <integer>1</integer>" : ""

plist_content = <<~PLIST
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>Label</key>
      <string>#{label}</string>
      <key>ProgramArguments</key>
      <array>
          <string>/bin/bash</string>
          <string>#{wrapper}</string>
      </array>
      <key>StartCalendarInterval</key>
      <dict>
          <key>Hour</key>
          <integer>#{hour}</integer>
          <key>Minute</key>
          <integer>#{minute}</integer>#{weekday_entry}
      </dict>
      <key>StandardOutPath</key>
      <string>/dev/null</string>
      <key>StandardErrorPath</key>
      <string>/dev/null</string>
      <key>WorkingDirectory</key>
      <string>#{project_dir}</string>
      <key>EnvironmentVariables</key>
      <dict>
          <key>PATH</key>
          <string>#{path_value}</string>
          <key>HOME</key>
          <string>#{home_dir}</string>
      </dict>
  </dict>
  </plist>
PLIST

# Unload existing job if loaded
system("launchctl", "unload", plist_dest, err: "/dev/null", out: "/dev/null") if File.exist?(plist_dest)

# Write plist
File.write(plist_dest, plist_content)
puts "Wrote #{plist_dest}"

# Load the job
system("launchctl", "load", plist_dest)
puts "Loaded #{label}"

puts
formatted_time = format("%d:%02d %s", hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour), minute, hour >= 12 ? "PM" : "AM")
schedule_desc = weekly ? "Monday at #{formatted_time}" : "daily at #{formatted_time}"
puts "Schedule: #{schedule_desc}"
puts "Verify:   launchctl list | grep ai-digest"
log_file = weekly ? "weekly-digest.log" : "digest.log"
puts "Logs:     tail -f #{project_dir}/#{log_file}"
```

Note: removed the line that wrote a plist copy to the project directory — the plist is gitignored and generated, no need for a reference copy.

**Step 2: Add weekly plist and log to .gitignore**

Add to `.gitignore`:

```
com.ai-digest.weekly.plist
weekly-digest.log
```

Wait — `*.log` is already gitignored, so `weekly-digest.log` is covered. Just add the weekly plist pattern. Actually `com.ai-digest.plist` is already there. Add `com.ai-digest.weekly.plist`.

**Step 3: Commit**

```bash
git add bin/install .gitignore
git commit -m "feat: add --weekly flag to install script for Monday launchd job"
```

---

### Task 7: Update README

**Files:**
- Modify: `README.md`

**Step 1: Add weekly digest section to README**

Add a "Weekly Digest" section after the "Daily Schedule" section covering:
- What it does (curates top 5 from week's daily digests using Sonnet)
- Install: `ruby bin/install --weekly`
- Logs: `tail -f weekly-digest.log`
- Config: `weekly` section in `settings.yml`

**Step 2: Update project structure to include new files**

Add `bin/weekly-digest`, `bin/run-weekly-digest.sh` to the tree.

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add weekly digest section to README"
```

---

### Task 8: End-to-End Test

**No files to create. Manual verification.**

**Step 1: Test the weekly digest runs manually**

Run: `bundle exec ruby bin/weekly-digest`

Expected: Reads available daily digests, calls Sonnet, posts to Slack, saves `digests/weekly-YYYY-MM-DD.md`.

Note: If only 1 daily digest exists, that's fine — it curates from whatever is available.

**Step 2: Install the weekly launchd job for testing**

Schedule it ~1 minute from now to verify launchd triggers it:

```bash
ruby bin/install --weekly HH:MM  # set to ~1 min from now
```

Wait for it to fire, then check `weekly-digest.log`.

**Step 3: Set the real schedule**

```bash
ruby bin/install --weekly 10:00
```

Verify: `launchctl list | grep ai-digest` should show both `com.ai-digest` and `com.ai-digest.weekly`.

**Step 4: Commit any final changes**

```bash
git add -A
git commit -m "feat: complete weekly best-of digest feature"
```
