# test/test_helper.rb
require "minitest/autorun"
require "minitest/spec"
require "minitest/reporters"
require "odsl"

Minitest::Reporters.use!

# ActiveRecord in-memory setup for audit tests
require "active_record"
require "sqlite3"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.define do
  create_table :odsl_execution_contexts, force: true do |t|
    t.string   :idempotency_key, null: false
    t.string   :service_class,   null: false
    t.string   :method_name,     null: false
    t.text     :kwargs
    t.string   :status,          null: false, default: "pending"
    t.datetime :expires_at
    t.timestamps
  end
  add_index :odsl_execution_contexts, :idempotency_key, unique: true
  add_index :odsl_execution_contexts, :expires_at

  create_table :odsl_step_records, force: true do |t|
    t.references :execution_context, null: false,
                 foreign_key: { to_table: :odsl_execution_contexts }
    t.string   :name,          null: false
    t.integer  :step_index,    null: false
    t.string   :status,        null: false, default: "pending"
    t.text     :result
    t.text     :error_message
    t.boolean  :non_resumable, default: false
    t.datetime :started_at
    t.datetime :completed_at
  end
end
