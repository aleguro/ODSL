require_relative "builder"
require_relative "runners"
require_relative "methods"
require_relative "configurable"

module Odsl
  class Dsl
    include Runners
    include Methods
    extend Configurable

    def initialize(**kwargs)

      @kwargs          = kwargs
      @context         = {}
      @last_results    = []
      @with_attributes = nil
      @finish_with     = nil
  
      kwargs.each do |key, value|
        instance_variable_set("@#{key}", value)
        @context[key] = value
      end     
    end

    class << self
      attr_reader :inmutable_mode

      def inmutable(bool)
        @inmutable_mode = bool
      end
    end   
  
    protected

    def build(*modules)
      @last_results = [ Odsl::Builder.build(*modules).new ]
      self
    end
  
    def with(*arguments)
      @with_attributes = arguments
      self
    end
  
    def value_return(with)
      @finish_with = with
    end
     
    alias make      call
    alias link      call
    alias get       to
    alias execute   run
  end
end
