# AI Digest — Design Document

**Date:** 2026-02-22
**Status:** Approved

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
│   └── digest              # Main entry point
├── lib/
│   ├── ai_digest/
│   │   ├── fetcher.rb      # Source fetching (RSS, web scraping)
│   │   ├── summarizer.rb   # Claude Haiku via Bedrock
│   │   ├── slack_poster.rb # Slack webhook posting
│   │   └── storage.rb      # Local markdown storage
│   └── ai_digest.rb        # Config loading, orchestration
├── config/
│   ├── sources.yml          # Source URLs and types
│   └── settings.yml         # Topics, Slack webhook, AWS config, storage path
├── digests/                 # Generated daily markdown files
├── Gemfile
└── README.md
```

Project location: `~/ai-digest/`

## Components

### 1. Fetcher

Supports two source types:

- **RSS feeds** — Parsed with the `feedjira` gem. Fetches items from the last 24 hours.
- **Web scraping** — For sources without RSS. Uses `nokogiri` + `net/http` to pull and parse HTML.

Each source is configured in `config/sources.yml`:

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

Prompt template:

> Here are today's items from AI/tech sources. Filter to only items relevant to these topics: {topics}. For each relevant item, provide: title, source, 2-3 sentence summary, and topic tags. Rank by importance. Return at most {max_items} items.

Configuration in `config/settings.yml`:

```yaml
topics:
  - "AI coding agents and assistants"
  - "Developer workflow tooling and automation"
  - "LLM model releases and capabilities"

max_items_per_digest: 10

bedrock:
  region: "us-east-1"
  model_id: "anthropic.claude-haiku-4-0-v1"
```

### 3. Slack Poster

Posts to a TED Slack channel via incoming webhook. The webhook URL is stored in an environment variable (`AI_DIGEST_SLACK_WEBHOOK`).

Digest format:

```
AI Digest — Feb 22, 2026

1. Claude Code Hooks API Released
   Source: Anthropic Blog | Tags: coding-agent, claude-code
   New hooks system allows shell commands to execute in response
   to tool calls. Enables custom validation and workflow automation.
   https://...

2. GPT-5.1 Benchmarks Show...
   Source: OpenAI Blog | Tags: model-release
   ...

[up to 10 items]

Full digest saved to ~/ai-digest/digests/2026-02-22.md
```

### 4. Local Storage

Each day's digest is saved as `digests/YYYY-MM-DD.md` with the same content as the Slack message plus raw URLs and metadata. Searchable with `rg`.

### 5. Scheduling

A macOS launchd plist runs `bin/digest` daily at a configurable time (default: 7:00 AM). If the machine is asleep, launchd runs it on next wake.

## Dependencies

### Gems

- `feedjira` — RSS/Atom feed parsing
- `nokogiri` — HTML parsing (for web scraping sources)
- `aws-sdk-bedrockruntime` — Claude Haiku via Amazon Bedrock
- `net/http` — HTTP requests (stdlib)

### External

- Amazon Bedrock access (TED AWS account)
- Slack incoming webhook (TED workspace, requires app creation)
- macOS launchd for scheduling

## Source List (Tier 1)

| Source | Type | Category |
|--------|------|----------|
| AI News (smol.ai) | RSS | Aggregator |
| Simon Willison's blog | RSS | Practitioner blog |
| Latent Space | RSS | Newsletter |
| Anthropic Engineering Blog | RSS | Lab blog |
| OpenAI Blog | RSS | Lab blog |
| Google DeepMind Blog | RSS | Lab blog |
| Hacker News (front page) | RSS | Aggregator |

## Future Enhancements (Not in v1)

- Additional Tier 2 sources (Alpha Signal, r/ClaudeAI, Cursor blog, etc.)
- Keyword/topic filter changes via Slack command
- Weekly trend summary in addition to daily digest
- Deduplication across sources
