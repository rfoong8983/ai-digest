# AI Digest — Design Document

## Overview

A Ruby CLI app (`ai-digest`) that runs daily via macOS launchd. It fetches content from curated AI/tech sources, filters and summarizes using Claude Haiku via Amazon Bedrock, posts a formatted digest to a TED Slack channel, and saves it as a local markdown file.

## Goals

1. **Tool discovery** — Find and evaluate new AI coding tools, agents, and integrations
2. **Strategic awareness** — Stay informed on industry trends and shifts for tooling/process decisions
3. **Configurable topics** — Adjust focus areas without code changes
4. **15-30 min daily reading time** — Pre-filtered, summarized, scannable

## Architecture

```
ai-digest/
├── bin/
│   ├── digest              # Daily digest entry point
│   ├── weekly-digest       # Weekly digest entry point
│   ├── install             # Generates and installs launchd plist(s)
│   ├── run-digest.sh       # Wrapper script for daily launchd job
│   └── run-weekly-digest.sh  # Wrapper script for weekly launchd job
├── lib/
│   ├── ai_digest/
│   │   ├── fetcher.rb      # RSS feed fetching (feedjira)
│   │   ├── summarizer.rb   # Claude Haiku via Bedrock
│   │   ├── weekly_curator.rb # Claude Sonnet weekly curation
│   │   ├── slack_poster.rb # Slack webhook posting
│   │   └── storage.rb      # Local markdown storage
│   └── ai_digest.rb        # Module + config loading
├── config/
│   ├── sources.yml          # RSS source list
│   ├── settings.yml         # Base configuration
│   └── settings.local.yml   # Local overrides (gitignored)
├── digests/                 # Saved daily and weekly digests (gitignored)
├── test/                    # Minitest + webmock tests
├── Gemfile
└── README.md
```

## Components

### 1. Fetcher

Fetches RSS feeds using the `feedjira` gem. Items from the last 24 hours are returned.

Each item includes:
- `title`, `url` — from the RSS entry's `<link>` element
- `article_url` — from the RSS entry's `<guid>`/`<id>` when it's a valid URL, otherwise falls back to `url`. For aggregators like Hacker News, this captures the discussion page URL (e.g., `news.ycombinator.com/item?id=...`) separately from the external link.
- `summary`, `source`, `category`, `published`

Sources are configured in `config/sources.yml`:

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

### 2. Summarizer (Claude Haiku via Bedrock)

Sends fetched items to Claude Haiku via Amazon Bedrock using the `aws-sdk-bedrockruntime` gem.

The prompt includes both `URL` and `Article-URL` for each item and asks the model to return both in the output JSON. This preserves the distinction between a project's URL and the source article that discusses it.

Output fields: `title`, `source`, `summary`, `tags`, `url`, `article_url`

Configuration in `config/settings.yml`:

```yaml
topics:
  - "AI coding agents and assistants"
  - "Developer workflow tooling and automation"
  - "LLM model releases and capabilities"

max_items_per_digest: 10

bedrock:
  region: "us-east-1"
  model_id: "us.anthropic.claude-haiku-4-5-20251001-v1:0"
```

### 3. Slack Poster

Posts to a TED Slack channel via incoming webhook. Supports both a production and test webhook.

Webhook resolution order:
1. `slack.webhook_url` in `config/settings.local.yml`
2. `AI_DIGEST_SLACK_WEBHOOK` environment variable

When `--test` flag is passed, uses `slack.test_webhook_url` from config instead.

Titles are formatted as Slack mrkdwn links using `article_url` (falling back to `url`), so they're clickable and link to the source article/discussion page.

Daily digest format:

```
AI Digest — Feb 22, 2026

1. *<https://news.ycombinator.com/item?id=...|Claude Code Hooks API Released>*
   Source: Hacker News | Tags: coding-agent, claude-code
   New hooks system allows shell commands to execute in response
   to tool calls. Enables custom validation and workflow automation.
   https://github.com/anthropics/claude-code

2. *<https://openai.com/blog/gpt5|GPT-5.1 Benchmarks Show...>*
   Source: OpenAI Blog | Tags: model-release
   ...

[up to 10 items]
```

### 4. Local Storage

Each day's digest is saved as `digests/YYYY-MM-DD.md` in markdown format. When `article_url` differs from `url`, a `[Source](article_url)` link is included alongside `[Read more](url)` so the weekly curator can pick up both URLs.

### 5. Scheduling

A macOS launchd plist runs `bin/digest` daily at a configurable time (default: 10:00 AM). If the machine is asleep, launchd runs it on next wake. Install via `ruby bin/install`.

## Dependencies

### Gems

- `feedjira` — RSS/Atom feed parsing
- `aws-sdk-bedrockruntime` — Claude Haiku via Amazon Bedrock
- `net/http` — HTTP requests (stdlib)

### External

- Amazon Bedrock access (TED AWS account)
- Slack incoming webhook (TED workspace, requires app creation)
- macOS launchd for scheduling

## Source List

| Source | Type | Category |
|--------|------|----------|
| AI News (smol.ai) | RSS | Aggregator |
| Simon Willison's blog | RSS | Practitioner blog |
| Latent Space | RSS | Newsletter |
| Anthropic Engineering Blog | RSS | Lab blog |
| OpenAI Blog | RSS | Lab blog |
| Google DeepMind Blog | RSS | Lab blog |
| Hacker News (front page) | RSS | Aggregator |

## Future Enhancements

- Additional sources (Alpha Signal, r/ClaudeAI, Cursor blog, etc.)
- Keyword/topic filter changes via Slack command
- Deduplication across sources
