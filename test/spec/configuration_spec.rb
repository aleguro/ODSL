# test/spec/configuration_spec.rb
require "test_helper"
require "odsl"

describe Odsl do
  describe ".configure" do
    before { Odsl.reset_config! }

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

    it "defaults lock_redis_url to nil" do
      assert_nil Odsl.config.lock_redis_url
    end

    it "sets lock_ttl" do
      Odsl.configure { |c| c.lock_ttl = 5_000 }
      assert_equal 5_000, Odsl.config.lock_ttl
    end

    it "defaults lock_ttl to 10_000" do
      assert_equal 10_000, Odsl.config.lock_ttl
    end

    it "reset_config! restores all defaults" do
      Odsl.configure do |c|
        c.background_adapter = :active_job
        c.audit_ttl          = 999
        c.lock_redis_url     = "redis://x"
        c.lock_ttl           = 1_000
      end
      Odsl.reset_config!
      assert_equal :thread,  Odsl.config.background_adapter
      assert_nil             Odsl.config.audit_ttl
      assert_nil             Odsl.config.lock_redis_url
      assert_equal 10_000,   Odsl.config.lock_ttl
    end

    it "configure without a block is a no-op" do
      assert_silent { Odsl.configure }
    end
  end
end
