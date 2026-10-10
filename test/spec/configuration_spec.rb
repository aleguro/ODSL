require "test_helper"
require "odsl"

describe Odsl do
  describe ".configure" do
    after { Odsl.reset_config! }

    it "sets background_adapter" do
      Odsl.configure { |c| c.background_adapter = :active_job }
      assert_equal :active_job, Odsl.config.background_adapter
    end

    it "defaults background_adapter to :thread" do
      assert_equal :thread, Odsl.config.background_adapter
    end

    it "sets audit_ttl" do
      Odsl.configure { |c| c.audit_ttl = 86_400 }
      assert_equal 86_400, Odsl.config.audit_ttl
    end

    it "defaults audit_ttl to nil" do
      assert_nil Odsl.config.audit_ttl
    end

    it "sets lock_redis_url" do
      Odsl.configure { |c| c.lock_redis_url = "redis://localhost:6379" }
      assert_equal "redis://localhost:6379", Odsl.config.lock_redis_url
    end

    it "sets lock_ttl" do
      Odsl.configure { |c| c.lock_ttl = 5_000 }
      assert_equal 5_000, Odsl.config.lock_ttl
    end

    it "defaults lock_ttl to 10_000" do
      assert_equal 10_000, Odsl.config.lock_ttl
    end
  end
end
