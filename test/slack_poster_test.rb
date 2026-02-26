# test/slack_poster_test.rb
require_relative "test_helper"
require "json"

class SlackPosterTest < Minitest::Test
  def setup
    AiDigest.reset_config!
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

  def teardown
    AiDigest.reset_config!
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

  def test_format_message_title_links_to_article_url
    items = [
      {
        "title" => "Cool Tool",
        "source" => "Hacker News",
        "summary" => "A tool for agents.",
        "tags" => ["dev-tooling"],
        "url" => "https://github.com/cool/tool",
        "article_url" => "https://news.ycombinator.com/item?id=123"
      }
    ]
    message = AiDigest::SlackPoster.format_message(items)

    assert_includes message, "<https://news.ycombinator.com/item?id=123|Cool Tool>"
    assert_includes message, "https://github.com/cool/tool"
  end

  def test_format_message_title_links_to_url_when_no_article_url
    items = [
      {
        "title" => "Blog Post",
        "source" => "Blog",
        "summary" => "A post.",
        "tags" => ["ai"],
        "url" => "https://blog.example.com/post-1"
      }
    ]
    message = AiDigest::SlackPoster.format_message(items)

    assert_includes message, "<https://blog.example.com/post-1|Blog Post>"
  end

  def test_post_sends_to_webhook_via_config
    stub_request(:post, "https://hooks.slack.com/services/test/webhook")
      .with { |req| JSON.parse(req.body).key?("text") }
      .to_return(status: 200, body: "ok")

    AiDigest.instance_variable_set(:@config, {
      "slack" => { "webhook_url" => "https://hooks.slack.com/services/test/webhook" }
    })
    result = AiDigest::SlackPoster.post(@digest_items)
    assert result
  end

  def test_post_sends_to_webhook_via_env
    stub_request(:post, "https://hooks.slack.com/services/test/env-webhook")
      .with { |req| JSON.parse(req.body).key?("text") }
      .to_return(status: 200, body: "ok")

    AiDigest.instance_variable_set(:@config, { "slack" => {} })
    ENV["AI_DIGEST_SLACK_WEBHOOK"] = "https://hooks.slack.com/services/test/env-webhook"
    result = AiDigest::SlackPoster.post(@digest_items)
    assert result
  ensure
    ENV.delete("AI_DIGEST_SLACK_WEBHOOK")
  end

  def test_post_returns_false_when_no_webhook
    ENV.delete("AI_DIGEST_SLACK_WEBHOOK")
    # Stub config to have no slack webhook, overriding settings.local.yml
    AiDigest.instance_variable_set(:@config, {
      "topics" => [],
      "max_items_per_digest" => 10,
      "slack" => {}
    })
    result = AiDigest::SlackPoster.post(@digest_items)
    refute result
  end

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

  def test_format_weekly_message_title_links_to_article_url
    weekly_result = {
      "themes" => [
        {
          "theme" => "Dev Tools",
          "items" => [
            {
              "title" => "Cool Tool",
              "source" => "Hacker News",
              "why_it_matters" => "Big deal.",
              "url" => "https://github.com/cool/tool",
              "article_url" => "https://news.ycombinator.com/item?id=123"
            }
          ]
        }
      ]
    }

    message = AiDigest::SlackPoster.format_weekly_message(weekly_result, Date.today - 6, Date.today)

    assert_includes message, "<https://news.ycombinator.com/item?id=123|Cool Tool>"
    assert_includes message, "https://github.com/cool/tool"
  end

  def test_post_weekly_sends_to_webhook
    stub_request(:post, "https://hooks.slack.com/services/test/webhook")
      .with { |req| JSON.parse(req.body)["text"].include?("Weekly Best of AI") }
      .to_return(status: 200, body: "ok")

    AiDigest.instance_variable_set(:@config, {
      "slack" => { "webhook_url" => "https://hooks.slack.com/services/test/webhook" }
    })

    weekly_result = { "themes" => [{ "theme" => "T", "items" => [{ "title" => "A", "source" => "S", "why_it_matters" => "W", "url" => "https://x.com" }] }] }
    result = AiDigest::SlackPoster.post_weekly(weekly_result, Date.today - 6, Date.today)
    assert result
  end

  def test_post_weekly_returns_false_when_no_webhook
    ENV.delete("AI_DIGEST_SLACK_WEBHOOK")
    AiDigest.instance_variable_set(:@config, { "slack" => {} })
    result = AiDigest::SlackPoster.post_weekly({ "themes" => [] }, Date.today - 6, Date.today)
    refute result
  end

  def test_post_uses_test_webhook_when_test_flag_set
    stub_request(:post, "https://hooks.slack.com/services/test/test-webhook")
      .with { |req| JSON.parse(req.body).key?("text") }
      .to_return(status: 200, body: "ok")

    AiDigest.instance_variable_set(:@config, {
      "slack" => {
        "webhook_url" => "https://hooks.slack.com/services/test/prod-webhook",
        "test_webhook_url" => "https://hooks.slack.com/services/test/test-webhook"
      }
    })

    result = AiDigest::SlackPoster.post(@digest_items, test: true)
    assert result
  end

  def test_post_uses_prod_webhook_when_test_flag_false
    stub_request(:post, "https://hooks.slack.com/services/test/prod-webhook")
      .with { |req| JSON.parse(req.body).key?("text") }
      .to_return(status: 200, body: "ok")

    AiDigest.instance_variable_set(:@config, {
      "slack" => {
        "webhook_url" => "https://hooks.slack.com/services/test/prod-webhook",
        "test_webhook_url" => "https://hooks.slack.com/services/test/test-webhook"
      }
    })

    result = AiDigest::SlackPoster.post(@digest_items, test: false)
    assert result
  end

  def test_post_returns_false_when_test_flag_set_but_no_test_webhook
    AiDigest.instance_variable_set(:@config, {
      "slack" => {
        "webhook_url" => "https://hooks.slack.com/services/test/prod-webhook"
      }
    })

    result = AiDigest::SlackPoster.post(@digest_items, test: true)
    refute result
  end

  def test_post_weekly_uses_test_webhook_when_test_flag_set
    stub_request(:post, "https://hooks.slack.com/services/test/test-webhook")
      .with { |req| JSON.parse(req.body)["text"].include?("Weekly Best of AI") }
      .to_return(status: 200, body: "ok")

    AiDigest.instance_variable_set(:@config, {
      "slack" => {
        "webhook_url" => "https://hooks.slack.com/services/test/prod-webhook",
        "test_webhook_url" => "https://hooks.slack.com/services/test/test-webhook"
      }
    })

    weekly_result = { "themes" => [{ "theme" => "T", "items" => [{ "title" => "A", "source" => "S", "why_it_matters" => "W", "url" => "https://x.com" }] }] }
    result = AiDigest::SlackPoster.post_weekly(weekly_result, Date.today - 6, Date.today, test: true)
    assert result
  end
end
