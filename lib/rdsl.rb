# frozen_string_literal: true

require_relative "rdsl/version"

module Rdsl
  class Error < StandardError; end

  class Dsl
  
    def initialize(**kwargs)

      @last_results    = []
      @with_attributes = nil
      @finish_with     = nil
  
      kwargs.each do |key, value|
        instance_variable_set("@#{key}", value)
        @context[key] = value
      end     
    end
  
    # Workflow metadata
    class << self
      attr_reader :run_in_main
  
      def main(&block)
        @run_in_main = block
      end
    end
  
    # MAIN
    def run
     
      instance_eval(&self.class.run_in_main)

      complete
    end
  
    protected
  
    def with(*arguments)
      @with_attributes = arguments
      self
    end
  
    def finish_with(with)
      @finish_with = with
    end
  
    def complete
      instance_variable_get "@#{@finish_with}"
    end
  
    def call(methodo)
      
      @last_results = send(methodo, *@with_attributes.map { |attribute| instance_variable_get("@#{attribute}") })
      @last_results = [@last_results] if @last_results.is_not_a? Array
  
      self
    end
  
    def to(*variables)
      variables.each_with_index do |variable, index|
        instance_variable_set("@#{variable}", @last_results[index])
      end
  
      self
    end
  
    alias create    call
    alias set       call
    alias link      call
    alias get       to
    alias execute   run
  end
end
