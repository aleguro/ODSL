module Odsl
  module Methods

    def use(object)
      @delegated = instance_variable_get("@#{object}")

      self
    end

    def call(methodo)

      run_method(methodo)
      restore_delegate

      self
    end
  
    def to(*variables)
      variables.each_with_index do |variable, index|
        instance_variable_set("@#{variable}", @last_results[index])
      end
  
      self
    end

    private

    def run_method(methodo)
      @last_results = @delegated.send(methodo, *with_attributes_resolver)
      @last_results = [ @last_results ] unless @last_results.is_a? Array
    end

    def restore_delegate
      @delegated = self
    end

    def with_attributes_resolver
      @with_attributes.map { |attribute| instance_variable_get("@#{attribute}") }
    end
  end
end