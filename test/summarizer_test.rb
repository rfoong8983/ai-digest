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
      "bedrock" => { "region" => "us-east-1", "model_id" => "us.anthropic.claude-haiku-4-5-20251001-v1:0" }
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
