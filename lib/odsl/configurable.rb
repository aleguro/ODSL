module Odsl
  module Configurable
    def self.configuration
      @configuration ||= {}
    end
    
    def self.configure
      yield(configuration)
    end
  end
end