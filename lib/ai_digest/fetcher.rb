# lib/ai_digest/fetcher.rb
require "feedjira"
require "net/http"
require "uri"

module AiDigest
  class Fetcher
    HOURS_LOOKBACK = 24

    def self.fetch_all(sources)
      sources.flat_map { |source| fetch_source(source) }
    end

    def self.fetch_source(source)
      case source["type"]
      when "rss" then fetch_rss(source)
      else
        warn "Unknown source type: #{source['type']} for #{source['name']}"
        []
      end
    rescue StandardError => e
      warn "Error fetching #{source['name']}: #{e.message}"
      []
    end

    def self.fetch_rss(source)
      uri = URI(source["url"])
      response = Net::HTTP.get_response(uri)
      return [] unless response.is_a?(Net::HTTPSuccess)

      feed = Feedjira.parse(response.body)
      cutoff = Time.now - (HOURS_LOOKBACK * 60 * 60)

      feed.entries
        .select { |entry| entry.published && entry.published > cutoff }
        .map do |entry|
          {
            title: entry.title&.strip,
            url: entry.url || entry.entry_id,
            summary: entry.summary&.strip || entry.content&.strip&.slice(0, 500),
            source: source["name"],
            category: source["category"],
            published: entry.published
          }
        end
    end
  end
end
