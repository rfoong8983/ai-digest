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

  def test_fetch_captures_article_url_from_guid
    rss_with_guid = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>HN Feed</title>
          <item>
            <title>Cool AI Tool</title>
            <link>https://github.com/cool/tool</link>
            <guid>https://news.ycombinator.com/item?id=12345</guid>
            <description>A cool AI tool.</description>
            <pubDate>#{Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S %z')}</pubDate>
          </item>
        </channel>
      </rss>
    XML

    stub_request(:get, "https://example.com/hn.xml")
      .to_return(status: 200, body: rss_with_guid, headers: { "Content-Type" => "application/xml" })

    source = { "name" => "Hacker News", "url" => "https://example.com/hn.xml", "type" => "rss", "category" => "aggregator" }
    items = AiDigest::Fetcher.fetch_source(source)

    assert_equal 1, items.length
    assert_equal "https://github.com/cool/tool", items.first[:url]
    assert_equal "https://news.ycombinator.com/item?id=12345", items.first[:article_url]
  end

  def test_fetch_article_url_falls_back_to_url_when_guid_not_a_url
    # Atom feeds often use tag URIs for entry IDs, not URLs
    atom_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Blog Feed</title>
        <entry>
          <title>Blog Post</title>
          <link href="https://blog.example.com/post-1"/>
          <id>tag:blog.example.com,2026:post-1</id>
          <summary>A blog post.</summary>
          <published>#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}</published>
        </entry>
      </feed>
    XML

    stub_request(:get, "https://example.com/blog.xml")
      .to_return(status: 200, body: atom_xml, headers: { "Content-Type" => "application/xml" })

    source = { "name" => "Blog", "url" => "https://example.com/blog.xml", "type" => "rss", "category" => "blog" }
    items = AiDigest::Fetcher.fetch_source(source)

    assert_equal 1, items.length
    assert_equal "https://blog.example.com/post-1", items.first[:url]
    assert_equal "https://blog.example.com/post-1", items.first[:article_url]
  end
end
