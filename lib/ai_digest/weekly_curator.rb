require "aws-sdk-bedrockruntime"
require "json"
require "date"

module AiDigest
  class WeeklyCurator
    def self.load_week(config)
      storage_path = config.dig("storage", "path") || "digests"
      digests_path = if storage_path.start_with?("/")
        storage_path
      else
        File.join(AiDigest.root, storage_path)
      end
      lookback = config.dig("weekly", "lookback_days") || 7
      cutoff = Date.today - lookback + 1

      texts = []
      Dir.glob(File.join(digests_path, "*.md")).sort.each do |file|
        basename = File.basename(file, ".md")
        next if basename.start_with?("weekly-")
        begin
          file_date = Date.parse(basename)
        rescue Date::Error
          next
        end
        next if file_date < cutoff

        texts << File.read(file)
      end

      texts.join("\n\n---\n\n")
    end

    def self.build_prompt(digests_text, config)
      topics = config["topics"].map { |t| "- #{t}" }.join("\n")
      max_items = config.dig("weekly", "max_items") || 5

      <<~PROMPT
        You are an AI news curator creating a weekly "best of" digest. Below are the daily digests from this past week.

        Your job:
        1. Identify the #{max_items} most significant developments from the week
        2. Group them by theme (2-3 themes)
        3. If the same topic appeared multiple days or from multiple sources, that signals higher significance
        4. For each item, explain why it matters this week

        Focus on these topics:
        #{topics}

        Return a JSON object with this structure:
        {
          "themes": [
            {
              "theme": "Theme Name",
              "items": [
                {
                  "title": "Item title",
                  "source": "Source name",
                  "why_it_matters": "2-3 sentences on why this is significant this week",
                  "url": "https://..."
                }
              ]
            }
          ]
        }

        Total items across all themes must be at most #{max_items}.
        Return ONLY valid JSON — no markdown fences, no extra text.

        This week's daily digests:

        #{digests_text}
      PROMPT
    end

    def self.call_bedrock(prompt, config)
      client = Aws::BedrockRuntime::Client.new(
        region: config.dig("bedrock", "region")
      )

      response = client.converse(
        model_id: config.dig("weekly", "model_id"),
        messages: [
          { role: "user", content: [{ text: prompt }] }
        ],
        inference_config: { max_tokens: 4096 }
      )

      response.output.message.content.first.text
    end

    def self.parse_response(text)
      cleaned = text.gsub(/\A```json\s*/, "").gsub(/\s*```\z/, "").strip
      JSON.parse(cleaned)
    rescue JSON::ParserError => e
      warn "Failed to parse weekly curator response: #{e.message}"
      { "themes" => [] }
    end

    def self.curate(config)
      digests_text = load_week(config)
      return { "themes" => [] } if digests_text.empty?

      prompt = build_prompt(digests_text, config)
      response_text = call_bedrock(prompt, config)
      parse_response(response_text)
    end
  end
end
