# test/storage_test.rb
require_relative "test_helper"
require "tmpdir"
require "fileutils"

class StorageTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("ai-digest-test")
    @digest_items = [
      {
        "title" => "Test Article",
        "source" => "Test Blog",
        "summary" => "A test summary.",
        "tags" => ["test"],
        "url" => "https://example.com/test"
      }
    ]
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_save_creates_dated_markdown_file
    AiDigest::Storage.save(@digest_items, path: @tmpdir)

    expected_file = File.join(@tmpdir, "#{Date.today.strftime('%Y-%m-%d')}.md")
    assert File.exist?(expected_file), "Expected #{expected_file} to exist"

    content = File.read(expected_file)
    assert_includes content, "Test Article"
    assert_includes content, "https://example.com/test"
  end

  def test_save_creates_directory_if_missing
    nested = File.join(@tmpdir, "nested", "digests")
    AiDigest::Storage.save(@digest_items, path: nested)

    assert File.directory?(nested)
  end

  def test_save_handles_empty_digest
    AiDigest::Storage.save([], path: @tmpdir)

    expected_file = File.join(@tmpdir, "#{Date.today.strftime('%Y-%m-%d')}.md")
    content = File.read(expected_file)
    assert_includes content, "No relevant AI news found today"
  end

  def test_save_includes_article_url_in_markdown
    items_with_article_url = [
      {
        "title" => "Cool Tool",
        "source" => "HN",
        "summary" => "A cool tool.",
        "tags" => ["dev-tooling"],
        "url" => "https://github.com/cool/tool",
        "article_url" => "https://news.ycombinator.com/item?id=123"
      }
    ]

    AiDigest::Storage.save(items_with_article_url, path: @tmpdir)

    content = File.read(File.join(@tmpdir, "#{Date.today.strftime('%Y-%m-%d')}.md"))
    assert_includes content, "[Read more](https://github.com/cool/tool)"
    assert_includes content, "[Source](https://news.ycombinator.com/item?id=123)"
  end

  def test_save_omits_source_link_when_article_url_matches_url
    items_same_urls = [
      {
        "title" => "Blog Post",
        "source" => "Blog",
        "summary" => "A post.",
        "tags" => ["ai"],
        "url" => "https://blog.example.com/post-1",
        "article_url" => "https://blog.example.com/post-1"
      }
    ]

    AiDigest::Storage.save(items_same_urls, path: @tmpdir)

    content = File.read(File.join(@tmpdir, "#{Date.today.strftime('%Y-%m-%d')}.md"))
    assert_includes content, "[Read more](https://blog.example.com/post-1)"
    refute_includes content, "[Source]"
  end

  def test_save_weekly_creates_prefixed_file
    weekly_result = {
      "themes" => [
        {
          "theme" => "Test Theme",
          "items" => [
            {
              "title" => "Test Article",
              "source" => "Blog",
              "why_it_matters" => "It matters.",
              "url" => "https://example.com"
            }
          ]
        }
      ]
    }

    AiDigest::Storage.save_weekly(weekly_result, Date.today - 6, Date.today, path: @tmpdir)

    expected_file = File.join(@tmpdir, "weekly-#{Date.today.strftime('%Y-%m-%d')}.md")
    assert File.exist?(expected_file)

    content = File.read(expected_file)
    assert_includes content, "Weekly Best of AI"
    assert_includes content, "Test Theme"
    assert_includes content, "Test Article"
  end
end
