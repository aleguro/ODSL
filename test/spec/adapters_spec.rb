# test/spec/adapters_spec.rb
require "test_helper"
require "odsl"

describe Odsl::Adapters::Base do
  it "raises NotImplementedError on enqueue" do
    assert_raises(NotImplementedError) do
      Odsl::Adapters::Base.enqueue(
        service_class: "Foo",
        method_name:   "bar",
        kwargs:        {}
      )
    end
  end
end

describe Odsl::Adapters::Thread do
  it "enqueues by starting a Ruby Thread" do
    result = nil
    t = Odsl::Adapters::Thread.enqueue(
      service_class: "String",
      method_name:   "upcase",
      kwargs:        {},
      callable:      -> { result = "ran" }
    )
    assert_instance_of ::Thread, t
    t.value
    assert_equal "ran", result
  end
end
