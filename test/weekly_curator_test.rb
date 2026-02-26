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

  def test_load_week_reads_daily_files
    File.write(File.join(@tmpdir, "#{Date.today.strftime('%Y-%m-%d')}.md"), "# AI Digest — Today\n\n## 1. Today Article\nContent.")
    yesterday = Date.today - 1
    File.write(File.join(@tmpdir, "#{yesterday.strftime('%Y-%m-%d')}.md"), "# AI Digest — Yesterday\n\n## 1. Yesterday Article\nContent.")

    text = AiDigest::WeeklyCurator.load_week(@config)

    assert_includes text, "Today Article"
    assert_includes text, "Yesterday Article"
  end

  def test_load_week_skips_weekly_files
    File.write(File.join(@tmpdir, "weekly-#{Date.today.strftime('%Y-%m-%d')}.md"), "# Weekly\n\nstuff")
    File.write(File.join(@tmpdir, "#{Date.today.strftime('%Y-%m-%d')}.md"), "# AI Digest\n\n## 1. Daily Article\nContent.")

    text = AiDigest::WeeklyCurator.load_week(@config)

    assert_includes text, "Daily Article"
    refute_includes text, "Weekly"
  end

  def test_load_week_ignores_files_outside_lookback
    old_date = Date.today - 10
    File.write(File.join(@tmpdir, "#{old_date.strftime('%Y-%m-%d')}.md"), "# Old\n\n## 1. Old Article\nContent.")

    text = AiDigest::WeeklyCurator.load_week(@config)
    assert_equal "", text
  end

  def test_load_week_returns_empty_string_when_no_files
    text = AiDigest::WeeklyCurator.load_week(@config)
    assert_equal "", text
  end

  def test_build_prompt_includes_digests_and_config
    digests_text = "# AI Digest — Feb 23\n\n## 1. Article A\nSummary A."

    prompt = AiDigest::WeeklyCurator.build_prompt(digests_text, @config)

    assert_includes prompt, "Article A"
    assert_includes prompt, "5"  # max_items
    assert_includes prompt, "themes"
    assert_includes prompt, "why_it_matters"
    assert_includes prompt, "AI coding agents"
  end

  def test_build_prompt_requests_article_url_field
    digests_text = "# AI Digest — Feb 23\n\n## 1. Article A\nSummary A."

    prompt = AiDigest::WeeklyCurator.build_prompt(digests_text, @config)

    assert_includes prompt, "article_url"
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

  def test_load_week_excludes_boundary_day
    boundary_date = Date.today - 7
    File.write(File.join(@tmpdir, "#{boundary_date.strftime('%Y-%m-%d')}.md"),
      "# AI Digest\n\n## 1. Boundary Article\nContent.")

    text = AiDigest::WeeklyCurator.load_week(@config)
    assert_equal "", text
  end

  def test_curate_returns_empty_themes_when_no_digests
    result = AiDigest::WeeklyCurator.curate(@config)
    assert_equal({ "themes" => [] }, result)
  end
end
