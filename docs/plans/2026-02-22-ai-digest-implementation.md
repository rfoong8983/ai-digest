# AI Digest Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Ruby CLI tool that fetches AI news from RSS sources, filters/summarizes via Claude Haiku on Bedrock, posts a daily digest to Slack, and saves it locally as markdown.

**Architecture:** Ruby CLI app with four components (Fetcher, Summarizer, SlackPoster, Storage) orchestrated by a main `bin/digest` script. Config driven via YAML files. Scheduled daily via macOS launchd.

**Tech Stack:** Ruby 3.4, feedjira (RSS), aws-sdk-bedrockruntime (Claude Haiku), net/http (Slack webhook), minitest (testing)

---

### Task 1: Project Scaffolding

**Files:**
- Create: `Gemfile`
- Create: `bin/digest`
- Create: `lib/ai_digest.rb`
- Create: `config/sources.yml`
- Create: `config/settings.yml`
- Create: `.gitignore`

**Step 1: Create Gemfile**

```ruby
# Gemfile
source "https://rubygems.org"

gem "feedjira", "~> 3.2"
gem "aws-sdk-bedrockruntime", "~> 1"

group :test do
  gem "minitest", "~> 5.0"
  gem "webmock", "~> 3.0"
end
```

**Step 2: Create .gitignore**

```
digests/
.bundle/
vendor/
*.log
.env
```

**Step 3: Create config/sources.yml**

```yaml
sources:
  - name: "Simon Willison"
    url: "https://simonwillison.net/atom/everything/"
    type: rss
    category: practitioner-blog

  - name: "Anthropic Engineering"
    url: "https://www.anthropic.com/engineering/rss"
    type: rss
    category: lab-blog

  - name: "AI News (smol.ai)"
    url: "https://news.smol.ai/rss.xml"
    type: rss
    category: aggregator

  - name: "Latent Space"
    url: "https://www.latent.space/feed"
    type: rss
    category: newsletter

  - name: "OpenAI Blog"
    url: "https://openai.com/blog/rss.xml"
    type: rss
    category: lab-blog

  - name: "Google DeepMind Blog"
    url: "https://blog.google/technology/ai/rss/"
    type: rss
    category: lab-blog

  - name: "Hacker News"
    url: "https://hnrss.org/frontpage"
    type: rss
    category: aggregator
```

**Step 4: Create config/settings.yml**

```yaml
topics:
  - "AI coding agents and assistants"
  - "Developer workflow tooling and automation"
  - "LLM model releases and capabilities"

max_items_per_digest: 10

bedrock:
  region: "us-east-1"
  model_id: "us.anthropic.claude-haiku-4-5-v1"

storage:
  path: "digests"
```

**Step 5: Create lib/ai_digest.rb (module skeleton)**

```ruby
# lib/ai_digest.rb
require "yaml"
require "date"

module AiDigest
  class Error < StandardError; end

  def self.root
    File.expand_path("..", __dir__)
  end

  def self.config
    @config ||= YAML.load_file(File.join(root, "config", "settings.yml"))
  end

  def self.sources
    @sources ||= YAML.load_file(File.join(root, "config", "sources.yml"))["sources"]
  end
end

require_relative "ai_digest/fetcher"
require_relative "ai_digest/summarizer"
require_relative "ai_digest/slack_poster"
require_relative "ai_digest/storage"
```

**Step 6: Create bin/digest (stub)**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/ai_digest"

puts "ai-digest: not yet implemented"
```

**Step 7: Make bin/digest executable and run bundle install**

Run: `chmod +x bin/digest && bundle install`

**Step 8: Commit**

```bash
git add Gemfile Gemfile.lock bin/digest lib/ai_digest.rb config/sources.yml config/settings.yml .gitignore
git commit -m "feat: scaffold project with Gemfile, config, and module skeleton"
```

---

### Task 2: RSS Fetcher

**Files:**
- Create: `lib/ai_digest/fetcher.rb`
- Create: `test/test_helper.rb`
- Create: `test/fetcher_test.rb`

**Step 1: Create test helper**

```ruby
# test/test_helper.rb
require "minitest/autorun"
require "webmock/minitest"
require_relative "../lib/ai_digest"
```

**Step 2: Write the failing test**

```ruby
# test/fetcher_test.rb
require_relative "test_helper"

class FetcherTest < Minitest::Test
  def setup
    @rss_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <title>New AI Coding Agent Released</title>
            <link>https://example.com/article-1</link>
            <description>A new AI coding agent was released today.</description>
            <pubDate>#{Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S %z')}</pubDate>
          </item>
          <item>
            <title>Old Article</title>
            <link>https://example.com/old</link>
            <description>This is old news.</description>
            <pubDate>#{(Time.now - 3 * 24 * 60 * 60).utc.strftime('%a, %d %b %Y %H:%M:%S %z')}</pubDate>
          </item>
        </channel>
      </rss>
    XML
  end

  def test_fetch_returns_recent_items_only
    stub_request(:get, "https://example.com/feed.xml")
      .to_return(status: 200, body: @rss_xml, headers: { "Content-Type" => "application/xml" })

    source = { "name" => "Test", "url" => "https://example.com/feed.xml", "type" => "rss", "category" => "test" }
    items = AiDigest::Fetcher.fetch_source(source)

    assert_equal 1, items.length
    assert_equal "New AI Coding Agent Released", items.first[:title]
    assert_equal "https://example.com/article-1", items.first[:url]
    assert_equal "Test", items.first[:source]
  end

  def test_fetch_all_sources_aggregates
    stub_request(:get, "https://example.com/feed.xml")
      .to_return(status: 200, body: @rss_xml, headers: { "Content-Type" => "application/xml" })

    sources = [
      { "name" => "Test", "url" => "https://example.com/feed.xml", "type" => "rss", "category" => "test" }
    ]
    items = AiDigest::Fetcher.fetch_all(sources)

    assert_equal 1, items.length
  end

  def test_fetch_handles_network_error_gracefully
    stub_request(:get, "https://example.com/feed.xml").to_timeout

    source = { "name" => "Test", "url" => "https://example.com/feed.xml", "type" => "rss", "category" => "test" }
    items = AiDigest::Fetcher.fetch_source(source)

    assert_equal [], items
  end
end
```

**Step 3: Run test to verify it fails**

Run: `bundle exec ruby test/fetcher_test.rb`
Expected: FAIL — `AiDigest::Fetcher` not defined

**Step 4: Write minimal implementation**

```ruby
# lib/ai_digest/fetcher.rb
require "feedjira"
require "net/http"
require "uri"

module AiDigest
  class Fetcher
    HOURS_LOOKBACK = 24

    def self.fetch_all(sources)
      sources.flat_map { |source| fetch_source(source) }
    end

    def self.fetch_source(source)
      case source["type"]
      when "rss" then fetch_rss(source)
      else
        warn "Unknown source type: #{source['type']} for #{source['name']}"
        []
      end
    rescue StandardError => e
      warn "Error fetching #{source['name']}: #{e.message}"
      []
    end

    def self.fetch_rss(source)
      uri = URI(source["url"])
      response = Net::HTTP.get_response(uri)
      return [] unless response.is_a?(Net::HTTPSuccess)

      feed = Feedjira.parse(response.body)
      cutoff = Time.now - (HOURS_LOOKBACK * 60 * 60)

      feed.entries
        .select { |entry| entry.published && entry.published > cutoff }
        .map do |entry|
          {
            title: entry.title&.strip,
            url: entry.url || entry.entry_id,
            summary: entry.summary&.strip || entry.content&.strip&.slice(0, 500),
            source: source["name"],
            category: source["category"],
            published: entry.published
          }
        end
    end
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bundle exec ruby test/fetcher_test.rb`
Expected: PASS (3 tests, 0 failures)

**Step 6: Commit**

```bash
git add lib/ai_digest/fetcher.rb test/test_helper.rb test/fetcher_test.rb
git commit -m "feat: add RSS fetcher with 24-hour lookback and error handling"
```

---

### Task 3: Bedrock Summarizer

**Files:**
- Create: `lib/ai_digest/summarizer.rb`
- Create: `test/summarizer_test.rb`

**Step 1: Write the failing test**

```ruby
# test/summarizer_test.rb
require_relative "test_helper"
require "json"

class SummarizerTest < Minitest::Test
  def setup
    @items = [
      { title: "New AI Coding Agent", url: "https://example.com/1", summary: "An agent was released", source: "Test Blog", category: "lab-blog", published: Time.now },
      { title: "Recipe for Cake", url: "https://example.com/2", summary: "A delicious cake recipe", source: "Food Blog", category: "other", published: Time.now }
    ]
    @config = {
      "topics" => ["AI coding agents and assistants"],
      "max_items_per_digest" => 10,
      "bedrock" => { "region" => "us-east-1", "model_id" => "us.anthropic.claude-haiku-4-5-v1" }
    }
  end

  def test_build_prompt_includes_items_and_topics
    prompt = AiDigest::Summarizer.build_prompt(@items, @config)

    assert_includes prompt, "New AI Coding Agent"
    assert_includes prompt, "AI coding agents and assistants"
    assert_includes prompt, "10"
  end

  def test_parse_response_extracts_items
    response_text = <<~JSON
      [
        {
          "title": "New AI Coding Agent",
          "source": "Test Blog",
          "summary": "An agent was released that helps with coding.",
          "tags": ["coding-agent"],
          "url": "https://example.com/1"
        }
      ]
    JSON

    parsed = AiDigest::Summarizer.parse_response(response_text)

    assert_equal 1, parsed.length
    assert_equal "New AI Coding Agent", parsed.first["title"]
  end

  def test_parse_response_handles_malformed_json
    parsed = AiDigest::Summarizer.parse_response("not json at all")

    assert_equal [], parsed
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/summarizer_test.rb`
Expected: FAIL — `AiDigest::Summarizer` not defined

**Step 3: Write minimal implementation**

```ruby
# lib/ai_digest/summarizer.rb
require "aws-sdk-bedrockruntime"
require "json"

module AiDigest
  class Summarizer
    def self.summarize(items, config)
      return [] if items.empty?

      prompt = build_prompt(items, config)
      response_text = call_bedrock(prompt, config)
      parse_response(response_text)
    end

    def self.build_prompt(items, config)
      topics = config["topics"].map { |t| "- #{t}" }.join("\n")
      max_items = config["max_items_per_digest"]

      items_text = items.map.with_index(1) do |item, i|
        "#{i}. [#{item[:source]}] #{item[:title]}\n   URL: #{item[:url]}\n   Description: #{item[:summary]&.slice(0, 300)}"
      end.join("\n\n")

      <<~PROMPT
        You are an AI news curator. Below are today's items from various AI/tech sources.

        Filter to ONLY items relevant to these topics:
        #{topics}

        For each relevant item, return a JSON array of objects with these fields:
        - "title": the item title
        - "source": the source name
        - "summary": a 2-3 sentence summary of why this is relevant
        - "tags": array of short topic tags (e.g., "coding-agent", "model-release", "dev-tooling")
        - "url": the item URL

        Rank by importance. Return at most #{max_items} items.
        Return ONLY valid JSON — no markdown fences, no extra text.

        Items:
        #{items_text}
      PROMPT
    end

    def self.call_bedrock(prompt, config)
      client = Aws::BedrockRuntime::Client.new(
        region: config.dig("bedrock", "region")
      )

      response = client.converse(
        model_id: config.dig("bedrock", "model_id"),
        messages: [
          { role: "user", content: [{ text: prompt }] }
        ],
        inference_config: { max_tokens: 4096 }
      )

      response.output.message.content.first.text
    end

    def self.parse_response(text)
      # Strip markdown fences if present
      cleaned = text.gsub(/\A```json\s*/, "").gsub(/\s*```\z/, "").strip
      JSON.parse(cleaned)
    rescue JSON::ParserError => e
      warn "Failed to parse summarizer response: #{e.message}"
      []
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec ruby test/summarizer_test.rb`
Expected: PASS (3 tests, 0 failures)

Note: `call_bedrock` is not tested here — it requires live AWS credentials. We test `build_prompt` and `parse_response` which are the unit-testable parts.

**Step 5: Commit**

```bash
git add lib/ai_digest/summarizer.rb test/summarizer_test.rb
git commit -m "feat: add Bedrock summarizer with prompt builder and response parser"
```

---

### Task 4: Slack Poster

**Files:**
- Create: `lib/ai_digest/slack_poster.rb`
- Create: `test/slack_poster_test.rb`

**Step 1: Write the failing test**

```ruby
# test/slack_poster_test.rb
require_relative "test_helper"
require "json"

class SlackPosterTest < Minitest::Test
  def setup
    @digest_items = [
      {
        "title" => "Claude Code Hooks API Released",
        "source" => "Anthropic Blog",
        "summary" => "New hooks system allows shell commands to execute in response to tool calls.",
        "tags" => ["coding-agent", "claude-code"],
        "url" => "https://example.com/hooks"
      }
    ]
  end

  def test_format_message_includes_title_and_date
    message = AiDigest::SlackPoster.format_message(@digest_items)

    assert_includes message, "AI Digest"
    assert_includes message, Date.today.strftime("%b %d, %Y")
    assert_includes message, "Claude Code Hooks API Released"
    assert_includes message, "Anthropic Blog"
    assert_includes message, "coding-agent"
  end

  def test_format_message_handles_empty_digest
    message = AiDigest::SlackPoster.format_message([])

    assert_includes message, "No relevant AI news found today"
  end

  def test_post_sends_to_webhook
    stub_request(:post, "https://hooks.slack.com/services/test/webhook")
      .with { |req| JSON.parse(req.body).key?("text") }
      .to_return(status: 200, body: "ok")

    ENV["AI_DIGEST_SLACK_WEBHOOK"] = "https://hooks.slack.com/services/test/webhook"
    result = AiDigest::SlackPoster.post(@digest_items)
    assert result
  ensure
    ENV.delete("AI_DIGEST_SLACK_WEBHOOK")
  end

  def test_post_returns_false_when_no_webhook
    ENV.delete("AI_DIGEST_SLACK_WEBHOOK")
    result = AiDigest::SlackPoster.post(@digest_items)
    refute result
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/slack_poster_test.rb`
Expected: FAIL — `AiDigest::SlackPoster` not defined

**Step 3: Write minimal implementation**

```ruby
# lib/ai_digest/slack_poster.rb
require "net/http"
require "uri"
require "json"
require "date"

module AiDigest
  class SlackPoster
    def self.post(digest_items)
      webhook_url = ENV["AI_DIGEST_SLACK_WEBHOOK"]
      unless webhook_url
        warn "AI_DIGEST_SLACK_WEBHOOK not set — skipping Slack post"
        return false
      end

      message = format_message(digest_items)
      uri = URI(webhook_url)

      response = Net::HTTP.post(
        uri,
        JSON.generate({ text: message }),
        "Content-Type" => "application/json"
      )

      response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      warn "Error posting to Slack: #{e.message}"
      false
    end

    def self.format_message(digest_items)
      date = Date.today.strftime("%b %d, %Y")

      if digest_items.empty?
        return "AI Digest — #{date}\n\nNo relevant AI news found today."
      end

      items_text = digest_items.each_with_index.map do |item, i|
        tags = Array(item["tags"]).join(", ")
        [
          "#{i + 1}. *#{item['title']}*",
          "   Source: #{item['source']} | Tags: #{tags}",
          "   #{item['summary']}",
          "   #{item['url']}"
        ].join("\n")
      end.join("\n\n")

      "AI Digest — #{date}\n\n#{items_text}"
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec ruby test/slack_poster_test.rb`
Expected: PASS (4 tests, 0 failures)

**Step 5: Commit**

```bash
git add lib/ai_digest/slack_poster.rb test/slack_poster_test.rb
git commit -m "feat: add Slack poster with webhook integration and message formatting"
```

---

### Task 5: Local Storage

**Files:**
- Create: `lib/ai_digest/storage.rb`
- Create: `test/storage_test.rb`

**Step 1: Write the failing test**

```ruby
# test/storage_test.rb
require_relative "test_helper"
require "tmpdir"
require "fileutils"

class StorageTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("ai-digest-test")
    @digest_items = [
      {
        "title" => "Test Article",
        "source" => "Test Blog",
        "summary" => "A test summary.",
        "tags" => ["test"],
        "url" => "https://example.com/test"
      }
    ]
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_save_creates_dated_markdown_file
    AiDigest::Storage.save(@digest_items, path: @tmpdir)

    expected_file = File.join(@tmpdir, "#{Date.today.strftime('%Y-%m-%d')}.md")
    assert File.exist?(expected_file), "Expected #{expected_file} to exist"

    content = File.read(expected_file)
    assert_includes content, "Test Article"
    assert_includes content, "https://example.com/test"
  end

  def test_save_creates_directory_if_missing
    nested = File.join(@tmpdir, "nested", "digests")
    AiDigest::Storage.save(@digest_items, path: nested)

    assert File.directory?(nested)
  end

  def test_save_handles_empty_digest
    AiDigest::Storage.save([], path: @tmpdir)

    expected_file = File.join(@tmpdir, "#{Date.today.strftime('%Y-%m-%d')}.md")
    content = File.read(expected_file)
    assert_includes content, "No relevant AI news found today"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/storage_test.rb`
Expected: FAIL — `AiDigest::Storage` not defined

**Step 3: Write minimal implementation**

```ruby
# lib/ai_digest/storage.rb
require "date"
require "fileutils"

module AiDigest
  class Storage
    def self.save(digest_items, path: nil)
      path ||= File.join(AiDigest.root, AiDigest.config.dig("storage", "path") || "digests")
      FileUtils.mkdir_p(path)

      filename = "#{Date.today.strftime('%Y-%m-%d')}.md"
      filepath = File.join(path, filename)

      content = format_markdown(digest_items)
      File.write(filepath, content)

      filepath
    end

    def self.format_markdown(digest_items)
      date = Date.today.strftime("%B %d, %Y")

      if digest_items.empty?
        return "# AI Digest — #{date}\n\nNo relevant AI news found today.\n"
      end

      items_md = digest_items.each_with_index.map do |item, i|
        tags = Array(item["tags"]).map { |t| "`#{t}`" }.join(" ")
        [
          "## #{i + 1}. #{item['title']}",
          "",
          "**Source:** #{item['source']} | **Tags:** #{tags}",
          "",
          item["summary"],
          "",
          "[Read more](#{item['url']})",
          ""
        ].join("\n")
      end.join("\n---\n\n")

      "# AI Digest — #{date}\n\n#{items_md}"
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec ruby test/storage_test.rb`
Expected: PASS (3 tests, 0 failures)

**Step 5: Commit**

```bash
git add lib/ai_digest/storage.rb test/storage_test.rb
git commit -m "feat: add local markdown storage for daily digests"
```

---

### Task 6: Orchestrator (bin/digest)

**Files:**
- Modify: `bin/digest`
- Create: `test/integration_test.rb`

**Step 1: Write the failing integration test**

```ruby
# test/integration_test.rb
require_relative "test_helper"
require "tmpdir"
require "fileutils"

class IntegrationTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("ai-digest-test")

    @rss_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <title>New AI Coding Agent Released</title>
            <link>https://example.com/article-1</link>
            <description>A new AI coding agent was released today that helps developers.</description>
            <pubDate>#{Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S %z')}</pubDate>
          </item>
        </channel>
      </rss>
    XML
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_fetch_and_store_without_bedrock
    # Test the fetch → format → store pipeline (skipping Bedrock summarization)
    stub_request(:get, "https://example.com/feed.xml")
      .to_return(status: 200, body: @rss_xml, headers: { "Content-Type" => "application/xml" })

    sources = [{ "name" => "Test", "url" => "https://example.com/feed.xml", "type" => "rss", "category" => "test" }]
    items = AiDigest::Fetcher.fetch_all(sources)

    assert_equal 1, items.length

    # Simulate summarizer output (since we can't call Bedrock in tests)
    digest_items = [
      {
        "title" => items.first[:title],
        "source" => items.first[:source],
        "summary" => "A new AI coding agent was released.",
        "tags" => ["coding-agent"],
        "url" => items.first[:url]
      }
    ]

    filepath = AiDigest::Storage.save(digest_items, path: @tmpdir)
    assert File.exist?(filepath)

    content = File.read(filepath)
    assert_includes content, "New AI Coding Agent Released"
  end
end
```

**Step 2: Run test to verify it passes (this is an integration smoke test)**

Run: `bundle exec ruby test/integration_test.rb`
Expected: PASS

**Step 3: Implement bin/digest**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/ai_digest"

puts "AI Digest — #{Date.today.strftime('%B %d, %Y')}"
puts "=" * 40

# 1. Fetch from all sources
puts "\nFetching from #{AiDigest.sources.length} sources..."
items = AiDigest::Fetcher.fetch_all(AiDigest.sources)
puts "Found #{items.length} items from the last 24 hours."

if items.empty?
  puts "No items found. Exiting."
  exit 0
end

# 2. Summarize via Bedrock
puts "\nFiltering and summarizing via Claude Haiku..."
digest_items = AiDigest::Summarizer.summarize(items, AiDigest.config)
puts "#{digest_items.length} relevant items after filtering."

# 3. Post to Slack
puts "\nPosting to Slack..."
if AiDigest::SlackPoster.post(digest_items)
  puts "Posted to Slack successfully."
else
  puts "Slack post skipped or failed."
end

# 4. Save locally
filepath = AiDigest::Storage.save(digest_items)
puts "Saved digest to #{filepath}"

puts "\nDone!"
```

**Step 4: Run full test suite**

Run: `bundle exec ruby -e "Dir.glob('test/*_test.rb').each { |f| require_relative f }"`
Expected: All tests pass

**Step 5: Commit**

```bash
git add bin/digest test/integration_test.rb
git commit -m "feat: implement orchestrator in bin/digest connecting all components"
```

---

### Task 7: Launchd Scheduling

**Files:**
- Create: `com.ai-digest.plist`

**Step 1: Create launchd plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ai-digest</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/.mise/shims/ruby</string>
        <string>/path/to/ai-digest/bin/digest</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>7</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/path/to/ai-digest/digest.log</string>
    <key>StandardErrorPath</key>
    <string>/path/to/ai-digest/digest.log</string>
    <key>WorkingDirectory</key>
    <string>/path/to/ai-digest</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$HOME/.mise/shims:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
```

**Step 2: Commit the plist**

```bash
git add com.ai-digest.plist
git commit -m "feat: add launchd plist for daily scheduling at 7am"
```

**Step 3: Install the launchd job (manual — not automated)**

To activate, the user runs:
```bash
cp com.ai-digest.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.ai-digest.plist
```

To test immediately:
```bash
launchctl start com.ai-digest
```

To uninstall:
```bash
launchctl unload ~/Library/LaunchAgents/com.ai-digest.plist
rm ~/Library/LaunchAgents/com.ai-digest.plist
```

---

### Task 8: Manual End-to-End Test

**No files to create. This is a manual verification step.**

**Step 1: Set environment variables**

The user needs to:
1. Ensure AWS credentials are configured (for Bedrock access)
2. Create a Slack incoming webhook and set `AI_DIGEST_SLACK_WEBHOOK`

**Step 2: Run bin/digest manually**

Run: `cd /path/to/ai-digest && bundle exec ruby bin/digest`
Expected: Script fetches RSS feeds, calls Bedrock, posts to Slack, saves a markdown file.

**Step 3: Verify output**

Check:
- `digests/YYYY-MM-DD.md` exists with content
- Slack channel has the digest message
- `digest.log` has no errors

**Step 4: Final commit (if any adjustments needed)**

```bash
git add -A
git commit -m "chore: finalize and polish for first run"
```

---

## Prerequisites Checklist (for the user)

Before running, the user needs to:

1. [ ] AWS credentials configured with Bedrock access (`~/.aws/credentials` or env vars)
2. [ ] Verify the Bedrock model ID is accessible in their region (check: `aws bedrock list-foundation-models --query "modelSummaries[?contains(modelId, 'claude')]"`)
3. [ ] Create a Slack app with incoming webhook at TED workspace
4. [ ] Set `AI_DIGEST_SLACK_WEBHOOK` environment variable
5. [ ] Run `bundle install` in the project directory
