# Weekly Best-Of Digest — Design

## Overview

A weekly "best of" digest that reads the last 7 days of saved daily digests, curates the top 5 most significant items using Claude Sonnet (stronger model than the daily Haiku), and posts a themed weekly summary to the same Slack channel.

## Schedule

- **When:** Monday at 10:00 AM
- **Trigger:** Separate launchd job (`com.ai-digest.weekly`)
- **Install:** `bin/install --weekly` (opt-in, separate from daily)

## Data Flow

1. `bin/weekly-digest` reads `.md` files from `digests/` for the last 7 days
2. `WeeklyCurator` parses items (title, source, summary, tags, url) from markdown
3. Sends all items to Claude Sonnet via Bedrock with a curation prompt that:
   - Detects themes and repeated topics across days
   - Weighs items that appeared from multiple sources higher
   - Ranks by significance and relevance
4. Sonnet returns top 5 items grouped by theme, each with a "why it matters" framing
5. Posts to Slack (same channel as daily) with a "Weekly Best Of" format
6. Saves to `digests/weekly-YYYY-MM-DD.md`

## New Files

- `lib/ai_digest/weekly_curator.rb` — reads daily digests, parses items, builds prompt, calls Sonnet, parses response
- `bin/weekly-digest` — orchestrator (mirrors `bin/digest`)
- `bin/run-weekly-digest.sh` — launchd wrapper (mirrors `bin/run-digest.sh`)
- `test/weekly_curator_test.rb` — tests for markdown parsing, prompt building, response parsing

## Config

New section in `settings.yml`:

```yaml
weekly:
  model_id: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  max_items: 5
  lookback_days: 7
```

## Install Script

`bin/install` gains a `--weekly` flag:

- `bin/install` — installs daily job only (existing behavior)
- `bin/install --weekly` — installs weekly job only (Monday 10 AM)
- Time argument still works: `bin/install --weekly 9:00`

Weekly job label: `com.ai-digest.weekly`

## Slack Message Format

```
Weekly Best of AI — Feb 17-23, 2026

Theme: Agentic Engineering Practices

1. *Agentic Engineering Patterns*
   Source: Simon Willison
   Why it matters: ...

2. *Writing code is cheap now*
   Source: Simon Willison
   Why it matters: ...

Theme: Model Capabilities

3. *The Claude C Compiler*
   Source: Simon Willison
   Why it matters: ...

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
