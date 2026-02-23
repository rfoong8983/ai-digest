# AI Digest

A Ruby CLI tool that fetches AI/tech news from curated RSS sources, filters and summarizes using Claude Haiku via Amazon Bedrock, posts a daily digest to Slack, and saves a local markdown copy.

## Prerequisites

- Ruby 3.4+ (via mise/rbenv)
- AWS CLI configured with Bedrock access (`aws configure`)
- A Slack incoming webhook URL

## Setup

### 1. Install dependencies

```bash
bundle install
```

### 2. Configure Slack webhook

Create `config/settings.local.yml` (gitignored) with your real webhook URL:

```yaml
slack:
  webhook_url: "https://hooks.slack.com/services/YOUR/ACTUAL/WEBHOOK"
```

To get a webhook URL, create a [Slack Incoming Webhook](https://api.slack.com/messaging/webhooks) for your workspace.

Alternatively, set the `AI_DIGEST_SLACK_WEBHOOK` environment variable. The config file takes priority if both are set.

### 3. Verify AWS credentials

The summarizer calls Claude Haiku via Amazon Bedrock. Make sure your AWS credentials are configured:

```bash
aws bedrock list-foundation-models --region us-east-1 --output json | jq '.modelSummaries[] | select(.modelId | contains("claude"))'
```

## Usage

### Run manually

```bash
bundle exec ruby bin/digest
```

This will:
1. Fetch the last 24 hours of posts from 7 RSS sources
2. Filter and summarize using Claude Haiku via Bedrock
3. Post the digest to Slack
4. Save a markdown file to `digests/YYYY-MM-DD.md`

### Run tests

```bash
bundle exec ruby -Ilib:test -e "Dir.glob('test/**/*_test.rb').each { |f| require File.expand_path(f) }"
```

## Daily Schedule (macOS launchd)

The install script generates a launchd plist with paths derived from your environment (project location, HOME, ruby version manager). It runs the digest every day at 10:00 AM.

### Install the schedule

```bash
ruby bin/install           # defaults to 10:00 AM
ruby bin/install 8:30      # set to 8:30 AM
ruby bin/install 14:00     # set to 2:00 PM
```

This will:
- Detect your ruby version manager (rbenv or mise)
- Generate the plist with correct absolute paths
- Copy it to `~/Library/LaunchAgents/`
- Load the job

### Verify it's loaded

```bash
launchctl list | grep ai-digest
```

You should see a line with `com.ai-digest`. The first column is the PID (or `-` if not currently running), the second is the last exit status.

### Check logs

```bash
tail -f digest.log
```

### Unload / stop the schedule

```bash
launchctl unload ~/Library/LaunchAgents/com.ai-digest.plist
```

### Change the schedule

Re-run the install script with the new time:

```bash
ruby bin/install 9:00
```

**Note:** launchd jobs only run when your Mac is awake. If your Mac is asleep at 10 AM, the job will run the next time it wakes up.

## Configuration

### Topics (`config/settings.yml`)

Edit the `topics` list to change what gets filtered:

```yaml
topics:
  - "AI coding agents and assistants"
  - "Developer workflow tooling and automation"
  - "LLM model releases and capabilities"
```

### Sources (`config/sources.yml`)

Add or remove RSS sources:

```yaml
sources:
  - name: "Source Name"
    url: "https://example.com/rss.xml"
    type: rss
    category: lab-blog
```

### Local overrides (`config/settings.local.yml`)

Any keys in this file override `settings.yml`. This file is gitignored and is the right place for secrets and personal preferences.

## Project Structure

```
ai-digest/
  bin/
    digest                # Main entry point
    install               # Generates and installs launchd plist
    run-digest.sh         # Wrapper script for launchd
  lib/ai_digest.rb        # Module + config loading
  lib/ai_digest/
    fetcher.rb            # RSS feed fetching (feedjira)
    summarizer.rb         # Bedrock Claude Haiku filtering
    slack_poster.rb       # Slack webhook posting
    storage.rb            # Local markdown storage
  config/
    settings.yml          # Base configuration
    settings.local.yml    # Local overrides (gitignored)
    sources.yml           # RSS source list
  test/                   # Minitest + webmock tests
  digests/                # Saved daily digests (gitignored)
  com.ai-digest.plist # Generated launchd plist (reference copy)
```
