# lib/ai_digest.rb
require "yaml"
require "date"

module AiDigest
  class Error < StandardError; end

  def self.root
    File.expand_path("..", __dir__)
  end

  def self.config
    @config ||= begin
      base = YAML.load_file(File.join(root, "config", "settings.yml"))
      local_path = File.join(root, "config", "settings.local.yml")
      if File.exist?(local_path)
        local = YAML.load_file(local_path)
        deep_merge(base, local)
      else
        base
      end
    end
  end

  def self.deep_merge(base, override)
    base.merge(override) do |_key, old_val, new_val|
      old_val.is_a?(Hash) && new_val.is_a?(Hash) ? deep_merge(old_val, new_val) : new_val
    end
  end

  def self.sources
    @sources ||= YAML.load_file(File.join(root, "config", "sources.yml"))["sources"]
  end

  def self.reset_config!
    @config = nil
    @sources = nil
  end
end

# TODO: uncomment as modules are implemented
require_relative "ai_digest/fetcher"
require_relative "ai_digest/summarizer"
require_relative "ai_digest/slack_poster"
require_relative "ai_digest/storage"
