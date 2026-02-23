# lib/ai_digest/slack_poster.rb
require "net/http"
require "uri"
require "json"
require "date"

module AiDigest
  class SlackPoster
    def self.post(digest_items)
      webhook_url = AiDigest.config.dig("slack", "webhook_url") || ENV["AI_DIGEST_SLACK_WEBHOOK"]
      unless webhook_url
        warn "Slack webhook not configured — set slack.webhook_url in config/settings.local.yml or AI_DIGEST_SLACK_WEBHOOK env var"
        return false
      end

      message = format_message(digest_items)
      uri = URI(webhook_url)

      response = Net::HTTP.post(
        uri,
        JSON.generate({ text: message }),
        "Content-Type" => "application/json"
      )

      response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      warn "Error posting to Slack: #{e.message}"
      false
    end

    def self.format_message(digest_items)
      date = Date.today.strftime("%b %d, %Y")

      if digest_items.empty?
        return "AI Digest — #{date}\n\nNo relevant AI news found today."
      end

      items_text = digest_items.each_with_index.map do |item, i|
        tags = Array(item["tags"]).join(", ")
        [
          "#{i + 1}. *#{item['title']}*",
          "   Source: #{item['source']} | Tags: #{tags}",
          "   #{item['summary']}",
          "   #{item['url']}"
        ].join("\n")
      end.join("\n\n")

      "AI Digest — #{date}\n\n#{items_text}"
    end

    def self.post_weekly(weekly_result, start_date, end_date)
      webhook_url = AiDigest.config.dig("slack", "webhook_url") || ENV["AI_DIGEST_SLACK_WEBHOOK"]
      unless webhook_url
        warn "Slack webhook not configured — set slack.webhook_url in config/settings.local.yml or AI_DIGEST_SLACK_WEBHOOK env var"
        return false
      end

      message = format_weekly_message(weekly_result, start_date, end_date)
      uri = URI(webhook_url)

      response = Net::HTTP.post(
        uri,
        JSON.generate({ text: message }),
        "Content-Type" => "application/json"
      )

      response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      warn "Error posting to Slack: #{e.message}"
      false
    end

    def self.format_weekly_message(weekly_result, start_date, end_date)
      date_range = "#{start_date.strftime('%b %d')}-#{end_date.strftime('%d, %Y')}"
      themes = weekly_result["themes"] || []

      if themes.empty?
        return "Weekly Best of AI — #{date_range}\n\nNo notable items this week."
      end

      item_number = 0
      themes_text = themes.map do |theme|
        items_text = theme["items"].map do |item|
          item_number += 1
          [
            "#{item_number}. *#{item['title']}*",
            "   Source: #{item['source']}",
            "   #{item['why_it_matters']}",
            "   #{item['url']}"
          ].join("\n")
        end.join("\n\n")

        "*Theme: #{theme['theme']}*\n#{items_text}"
      end.join("\n\n")

      "Weekly Best of AI — #{date_range}\n\n#{themes_text}"
    end
  end
end
