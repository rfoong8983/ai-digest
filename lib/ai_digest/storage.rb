# lib/ai_digest/storage.rb
require "date"
require "fileutils"

module AiDigest
  class Storage
    def self.save(digest_items, path: nil)
      path ||= File.join(AiDigest.root, AiDigest.config.dig("storage", "path") || "digests")
      FileUtils.mkdir_p(path)

      filename = "#{Date.today.strftime('%Y-%m-%d')}.md"
      filepath = File.join(path, filename)

      content = format_markdown(digest_items)
      File.write(filepath, content)

      filepath
    end

    def self.format_markdown(digest_items)
      date = Date.today.strftime("%B %d, %Y")

      if digest_items.empty?
        return "# AI Digest — #{date}\n\nNo relevant AI news found today.\n"
      end

      items_md = digest_items.each_with_index.map do |item, i|
        tags = Array(item["tags"]).map { |t| "`#{t}`" }.join(" ")
        [
          "## #{i + 1}. #{item['title']}",
          "",
          "**Source:** #{item['source']} | **Tags:** #{tags}",
          "",
          item["summary"],
          "",
          "[Read more](#{item['url']})",
          ""
        ].join("\n")
      end.join("\n---\n\n")

      "# AI Digest — #{date}\n\n#{items_md}"
    end
  end
end
