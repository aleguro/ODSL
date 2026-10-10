module Odsl
  class Configuration
    attr_accessor :background_adapter, :audit_ttl,
                  :lock_redis_url, :lock_ttl

    def initialize
      @background_adapter = :thread
      @audit_ttl          = nil
      @lock_redis_url     = nil
      @lock_ttl           = 10_000
    end
  end

  class << self
    def configure
      yield(config)
    end

    def config
      @config ||= Configuration.new
    end

    def reset_config!
      @config = Configuration.new
    end
  end
end
