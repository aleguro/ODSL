module Odsl
  module Runners
    def run(method)

      instance_eval(method.to_s)

      if @finish_with.is_a? Array
      
        @finish_with.map { |variable| instance_variable_get("@#{variable}") }
      else
        instance_variable_get "@#{@finish_with}"
      end
    end
  end
end