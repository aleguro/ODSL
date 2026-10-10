require "rails/generators"
require "rails/generators/active_record"

module Odsl
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Creates an Odsl initializer and migration for audit tables"

      def create_initializer
        template "odsl_initializer.rb.erb", "config/initializers/odsl.rb"
      end

      def create_migration
        migration_template "create_odsl_tables.rb.erb",
                           "db/migrate/create_odsl_tables.rb"
      end
    end
  end
end
