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
        lines = [
          "## #{i + 1}. #{item['title']}",
          "",
          "**Source:** #{item['source']} | **Tags:** #{tags}",
          "",
          item["summary"],
          "",
          "[Read more](#{item['url']})"
        ]
        if item["article_url"] && item["article_url"] != item["url"]
          lines << " | [Source](#{item['article_url']})"
        end
        lines << ""
        lines.join("\n")
      end.join("\n---\n\n")

      "# AI Digest — #{date}\n\n#{items_md}"
    end

    def self.save_weekly(weekly_result, start_date, end_date, path: nil)
      path ||= File.join(AiDigest.root, AiDigest.config.dig("storage", "path") || "digests")
      FileUtils.mkdir_p(path)

      filename = "weekly-#{end_date.strftime('%Y-%m-%d')}.md"
      filepath = File.join(path, filename)

      content = format_weekly_markdown(weekly_result, start_date, end_date)
      File.write(filepath, content)

      filepath
    end

    def self.format_weekly_markdown(weekly_result, start_date, end_date)
      date_range = "#{start_date.strftime('%B %d')} - #{end_date.strftime('%B %d, %Y')}"
      themes = weekly_result["themes"] || []

      if themes.empty?
        return "# Weekly Best of AI — #{date_range}\n\nNo notable items this week.\n"
      end

      item_number = 0
      themes_md = themes.map do |theme|
        items_md = theme["items"].map do |item|
          item_number += 1
          [
            "### #{item_number}. #{item['title']}",
            "",
            "**Source:** #{item['source']}",
            "",
            item["why_it_matters"],
            "",
            "[Read more](#{item['url']})",
            ""
          ].join("\n")
        end.join("\n")

        "## #{theme['theme']}\n\n#{items_md}"
      end.join("\n---\n\n")

      "# Weekly Best of AI — #{date_range}\n\n#{themes_md}"
    end
  end
end
