module Odsl
  module Methods
    def call(methodo)
      
      @last_results = send(methodo, *@with_attributes.map { |attribute| instance_variable_get("@#{attribute}") })
      @last_results = [@last_results] unless @last_results.is_a? Array
  
      self
    end
  
    def to(*variables)
      variables.each_with_index do |variable, index|
        instance_variable_set("@#{variable}", @last_results[index])
      end
  
      self
    end
  end
end