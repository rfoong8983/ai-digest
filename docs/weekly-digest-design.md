# Weekly Best-Of Digest — Design

## Overview

A weekly "best of" digest that reads the last 7 days of saved daily digests, curates the top 5 most significant items using Claude Sonnet (stronger model than the daily Haiku), and posts a themed weekly summary to the same Slack channel.

## Schedule

- **When:** Monday at 10:00 AM
- **Trigger:** Separate launchd job (`com.ai-digest.weekly`)
- **Install:** `bin/install --weekly` (opt-in, separate from daily)

## Data Flow

1. `bin/weekly-digest` reads `.md` files from `digests/` for the last 7 days
2. `WeeklyCurator` sends the raw markdown text to Claude Sonnet via Bedrock
3. Sonnet curation prompt:
   - Detects themes and repeated topics across days
   - Weighs items that appeared from multiple sources higher
   - Ranks by significance and relevance
4. Sonnet returns top 5 items grouped by theme, each with a "why it matters" framing and both `url` and `article_url` (when a `[Source]` link is available in the daily markdown)
5. Posts to Slack (same channel as daily, or test channel with `--test`) with a "Weekly Best Of" format
6. Saves to `digests/weekly-YYYY-MM-DD.md`

## Files

- `lib/ai_digest/weekly_curator.rb` — reads daily digests, builds prompt, calls Sonnet, parses response
- `bin/weekly-digest` — orchestrator (mirrors `bin/digest`), supports `--test` flag
- `bin/run-weekly-digest.sh` — launchd wrapper (mirrors `bin/run-digest.sh`)
- `test/weekly_curator_test.rb` — tests for week loading, prompt building, response parsing

## Config

Section in `settings.yml`:

```yaml
weekly:
  model_id: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  max_items: 5
  lookback_days: 7
```

## Install Script

`bin/install` with `--weekly` flag:

- `bin/install` — installs daily job only (existing behavior)
- `bin/install --weekly` — installs weekly job only (Monday 10 AM)
- Time argument still works: `bin/install --weekly 9:00`

Weekly job label: `com.ai-digest.weekly`

## Slack Message Format

Titles are clickable Slack mrkdwn links using `article_url` (the source discussion page), falling back to `url` when `article_url` is absent.

```
Weekly Best of AI — Feb 17-23, 2026

Theme: Agentic Engineering Practices

1. *<https://news.ycombinator.com/item?id=...|Agentic Engineering Patterns>*
   Source: Simon Willison
   Why it matters: ...
   https://simonwillison.net/2026/...

2. *<https://example.com/article|Writing code is cheap now>*
   Source: Latent Space
   Why it matters: ...
   https://example.com/article

Theme: Model Capabilities

3. *<https://anthropic.com/blog/...|The Claude C Compiler>*
   Source: Anthropic Engineering
   Why it matters: ...
   https://anthropic.com/blog/...

...
```

## Markdown Storage Format

Saved to `digests/weekly-YYYY-MM-DD.md` with similar structure, using `# Weekly Best of AI` header to distinguish from daily digests.

## Edge Cases

- Fewer than 7 daily digests available (new install): curate from whatever is available
- No daily digests found: post "No items to curate this week" and exit
- Daily digest has 0 items: skip that day's file

## Model

Uses Claude Sonnet (`us.anthropic.claude-sonnet-4-5-20250929-v1:0`) via Bedrock for stronger reasoning than the daily Haiku filter. Configurable in `settings.yml` under `weekly.model_id`.
