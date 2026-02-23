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
end
