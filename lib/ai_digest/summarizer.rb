require "aws-sdk-bedrockruntime"
require "json"

module AiDigest
  class Summarizer
    def self.summarize(items, config)
      return [] if items.empty?

      prompt = build_prompt(items, config)
      response_text = call_bedrock(prompt, config)
      parse_response(response_text)
    end

    def self.build_prompt(items, config)
      topics = config["topics"].map { |t| "- #{t}" }.join("\n")
      max_items = config["max_items_per_digest"]

      items_text = items.map.with_index(1) do |item, i|
        "#{i}. [#{item[:source]}] #{item[:title]}\n   URL: #{item[:url]}\n   Description: #{item[:summary]&.slice(0, 300)}"
      end.join("\n\n")

      <<~PROMPT
        You are an AI news curator. Below are today's items from various AI/tech sources.

        Filter to ONLY items relevant to these topics:
        #{topics}

        For each relevant item, return a JSON array of objects with these fields:
        - "title": the item title
        - "source": the source name
        - "summary": a 2-3 sentence summary of why this is relevant
        - "tags": array of short topic tags (e.g., "coding-agent", "model-release", "dev-tooling")
        - "url": the item URL

        Rank by importance. Return at most #{max_items} items.
        Return ONLY valid JSON — no markdown fences, no extra text.

        Items:
        #{items_text}
      PROMPT
    end

    def self.call_bedrock(prompt, config)
      client = Aws::BedrockRuntime::Client.new(
        region: config.dig("bedrock", "region")
      )

      response = client.converse(
        model_id: config.dig("bedrock", "model_id"),
        messages: [
          { role: "user", content: [{ text: prompt }] }
        ],
        inference_config: { max_tokens: 4096 }
      )

      response.output.message.content.first.text
    end

    def self.parse_response(text)
      # Strip markdown fences if present
      cleaned = text.gsub(/\A```json\s*/, "").gsub(/\s*```\z/, "").strip
      JSON.parse(cleaned)
    rescue JSON::ParserError => e
      warn "Failed to parse summarizer response: #{e.message}"
      []
    end
  end
end
