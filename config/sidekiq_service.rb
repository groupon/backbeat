# Copyright (c) 2015, Groupon, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# Neither the name of GROUPON nor the names of its contributors may be
# used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'sidekiq'
require 'sidekiq-failures'
require 'celluloid'
require_relative '../config/environment.rb'
require 'backbeat/workers/middleware/transaction_id'

module Sidekiq
  class Shutdown < RuntimeError; end
  class CLI; end
end

require 'celluloid/autostart'
require 'sidekiq/processor'

require 'sidekiq/launcher'
require 'backbeat/logging'
require 'backbeat/workers/middleware/transaction_id'

module Services
  class SidekiqService
    include Sidekiq::Util

    attr_accessor :config, :launcher

    CONFIG_OPTIONS_TO_STRIP = ['config_file', 'daemon', 'environment', 'pidfile', 'require', 'tag', 'options']

    def initialize(opts = {})
      @config = opts.reject { |k, _| CONFIG_OPTIONS_TO_STRIP.include?(k) }.merge(opts['options']).symbolize_keys
      @mutex = Mutex.new

      Sidekiq.configure_server do |config|
        config.redis = Backbeat::Config.redis
        config.poll_interval = 5
        config.failures_max_count = false
        config.failures_default_mode = :exhausted
        config.server_middleware do |chain|
          chain.add Backbeat::Workers::Middleware::TransactionId
        end
      end
    end

    def start
      # we have to manually boot sidekiq schedulable because of a torquebox sidekiq loading issue
      SidekiqSchedulable.boot!
      fire_event(:startup)

      Thread.new do
        @mutex.synchronize { run }
      end
    end

    def stop
      @mutex.synchronize { launcher.stop } if launcher
    end

    def run
      Sidekiq.options.merge!(config)
      Sidekiq.options[:queues] = Sidekiq.options[:queues].to_a
      raise 'Sidekiq workers must have at least 1 queue!' if Sidekiq.options[:queues].size < 1

      Sidekiq.logger = Backbeat::SidekiqLogger
      Celluloid.logger = Backbeat::SidekiqLogger

      @launcher = Sidekiq::Launcher.new(Sidekiq.options)
      launcher.run
    rescue => e
      puts e.message
      puts e.backtrace
    end
  end
end

