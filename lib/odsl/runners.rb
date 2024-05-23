module Odsl
  module Runners
    def run(method)

      instance_eval(method.to_s)
      instance_variable_get "@#{@finish_with}"
    end
  end
end