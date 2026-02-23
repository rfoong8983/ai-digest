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
    # Test the fetch -> format -> store pipeline (skipping Bedrock summarization)
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
