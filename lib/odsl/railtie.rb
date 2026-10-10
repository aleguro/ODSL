require "rails/railtie"

module Odsl
  class Railtie < Rails::Railtie
    rake_tasks do
      namespace :odsl do
        desc "Remove expired audit records"
        task cleanup: :environment do
          count = Odsl.cleanup_expired!
          puts "Removed #{count} expired execution context(s)"
        end
      end
    end
  end
end
