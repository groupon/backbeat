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

require 'securerandom'

module Backbeat
  module Logging
    LEVELS = [:debug, :info, :warn, :error, :fatal]

    LEVELS.each_with_index do |level, level_num|
      define_method(level) do |message = nil, &block|
        if block
          message = block.call
        end
        message_with_metadata = {
          time: Time.now.utc.iso8601(6),
          name: logging_name,
          data: message,
          pid: Process.pid,
          thread_id: Thread.current.object_id,
          tid: Logger.tid || 'none',
          revision: Config.revision
        }
        Logger.add(level_num, message_with_metadata)
      end
    end

    private

    def logging_name
      case self
      when Class
        self.to_s
      when Module
        self.to_s
      else
        self.class.to_s
      end
    end
  end

  class Logger
    extend Logging

    def self.logger
      @logger ||= create_logger
    end

    def self.logger=(logger)
      @logger = logger
    end

    def self.add(level_num, message)
      level = (Logging::LEVELS[level_num] || 'ANY').downcase
      log_data = message.merge({ level: level }).to_json + "\n"
      logger.add(level_num, log_data, nil)
    end

    def self.create_logger
      if defined?(TorqueBox)
        TorqueBox::Logger.new('backbeat_logger')
      else
        logger = ::Logger.new(Config.log_file)
        logger.level = Config.log_level
        logger.formatter = lambda { |_, _, _, msg| msg }
        logger
      end
    end

    def self.tid_store
      @tid ||= {}
    end

    def self.tid(option = nil)
      if option == :set
        self.tid = SecureRandom.uuid.to_s.slice(0,7)
      elsif option.kind_of?(String)
        self.tid = option
      elsif option == :clear
        self.tid = nil
      end
      tid_store[Thread.current.object_id]
    end

    def self.tid=(value)
      if value.nil?
        tid_store.delete(Thread.current.object_id)
      else
        tid_store[Thread.current.object_id] = value
      end
    end
  end

  class SidekiqLogger
    extend Logging
  end
end
