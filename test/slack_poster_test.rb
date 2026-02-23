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
end
