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

  CONFIG_MUTEX = Mutex.new

  class << self
    def configure
      yield(config) if block_given?
    end

    def config
      CONFIG_MUTEX.synchronize { @config ||= Configuration.new }
    end

    def reset_config!
      CONFIG_MUTEX.synchronize { @config = Configuration.new }
    end
  end
end
