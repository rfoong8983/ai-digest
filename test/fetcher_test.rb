require_relative "test_helper"

class FetcherTest < Minitest::Test
  def setup
    @rss_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <title>New AI Coding Agent Released</title>
            <link>https://example.com/article-1</link>
            <description>A new AI coding agent was released today.</description>
            <pubDate>#{Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S %z')}</pubDate>
          </item>
          <item>
            <title>Old Article</title>
            <link>https://example.com/old</link>
            <description>This is old news.</description>
            <pubDate>#{(Time.now - 3 * 24 * 60 * 60).utc.strftime('%a, %d %b %Y %H:%M:%S %z')}</pubDate>
          </item>
        </channel>
      </rss>
    XML
  end

  def test_fetch_returns_recent_items_only
    stub_request(:get, "https://example.com/feed.xml")
      .to_return(status: 200, body: @rss_xml, headers: { "Content-Type" => "application/xml" })

    source = { "name" => "Test", "url" => "https://example.com/feed.xml", "type" => "rss", "category" => "test" }
    items = AiDigest::Fetcher.fetch_source(source)

    assert_equal 1, items.length
    assert_equal "New AI Coding Agent Released", items.first[:title]
    assert_equal "https://example.com/article-1", items.first[:url]
    assert_equal "Test", items.first[:source]
  end

  def test_fetch_all_sources_aggregates
    stub_request(:get, "https://example.com/feed.xml")
      .to_return(status: 200, body: @rss_xml, headers: { "Content-Type" => "application/xml" })

    sources = [
      { "name" => "Test", "url" => "https://example.com/feed.xml", "type" => "rss", "category" => "test" }
    ]
    items = AiDigest::Fetcher.fetch_all(sources)

    assert_equal 1, items.length
  end

  def test_fetch_handles_network_error_gracefully
    stub_request(:get, "https://example.com/feed.xml").to_timeout

    source = { "name" => "Test", "url" => "https://example.com/feed.xml", "type" => "rss", "category" => "test" }
    items = AiDigest::Fetcher.fetch_source(source)

    assert_equal [], items
  end
end
