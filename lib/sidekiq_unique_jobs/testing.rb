# frozen_string_literal: true

# :nocov:
# :nodoc:

require "sidekiq"
require "sidekiq/testing"
require "sidekiq_unique_jobs/rspec/matchers"
require "sidekiq_unique_jobs/lock/validator"
require "sidekiq_unique_jobs/lock/client_validator"
require "sidekiq_unique_jobs/lock/server_validator"

#
# See Sidekiq gem for more details
#
module Sidekiq
  #
  # Temporarily turn Sidekiq's options into something different
  #
  # @note this method will restore the original options after yielding
  #
  # @param [Hash<Symbol, Object>] tmp_config the temporary config to use
  #
  def self.use_options(tmp_config = {})
    old_options = default_worker_options.dup

    default_worker_options.clear
    self.default_worker_options = tmp_config
    yield
  ensure
    default_worker_options.clear
    self.default_worker_options = DEFAULT_WORKER_OPTIONS
    self.default_worker_options = old_options
  end

  #
  # See Sidekiq::Worker in Sidekiq gem for more details
  #
  module Worker
    #
    # Adds class methods to Sidekiq::Worker
    #
    module ClassMethods
      #
      # Temporarily turn a workers sidekiq_options into something different
      #
      # @note this method will restore the original configuration after yielding
      #
      # @param [Hash<Symbol, Object>] tmp_config the temporary config to use
      #
      def use_options(tmp_config = {})
        old_options = sidekiq_options_hash.dup
        sidekiq_options(old_options.merge(tmp_config))

        yield
      ensure
        self.sidekiq_options_hash = Sidekiq::DEFAULT_WORKER_OPTIONS
        sidekiq_options(old_options)
      end
    end

    #
    # Prepends deletion of locks to clear_all
    #
    module Overrides
      #
      # Overrides sidekiq_options on the worker class to prepend validation
      #
      # @param [Hash] options worker options
      #
      # @return [void]
      #
      def sidekiq_options(options = {})
        SidekiqUniqueJobs.validate_worker!(options) if SidekiqUniqueJobs.config.raise_on_config_error

        super(options)
      end

      #
      # Prepends deletion of locks to clear
      #
      module ClassMethods
        #
        # Clears the jobs for this worker and removes all locks
        #
        def clear
          jobs.each do |job|
            SidekiqUniqueJobs::Unlockable.unlock(job)
          end

          super
        end
      end
    end

    prepend Overrides

    #
    # Prepends methods to Sidekiq::Worker
    #
    module ClassMethods
      prepend Overrides::ClassMethods
    end

    #
    # Prepends singleton methods to Sidekiq::Worker
    #
    module SignletonOverrides
      #
      # Clears all jobs for this worker and removes all locks
      #
      def clear_all
        super

        SidekiqUniqueJobs::Digests.new.delete_by_pattern("*", count: 10_000)
      end
    end

    singleton_class.prepend SignletonOverrides
  end
end
