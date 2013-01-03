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

module Backbeat
  class Config
    def self.environment
      @environment ||= ENV.fetch('RACK_ENV', 'development')
    end

    def self.root
      @root ||= File.expand_path('../../../', __FILE__)
    end

    def self.log_file
      @log_file ||= (
        ENV['LOG_FILE'] || options[:log] || STDOUT
      )
    end

    def self.log_level
      @log_level ||= (
        level = ENV['LOG_LEVEL'] || options[:log_level] || 'INFO'
        ::Logger.const_get(level)
      )
    end

    def self.options
      @options ||= (
        opts_yml = YAML.load_file("#{root}/config/options.yml")
        opts = opts_yml.fetch(environment, {})
        opts.default_proc = ->(h, k) { h.key?(k.to_s) ? h[k.to_s] : nil }
        opts
      )
    end

    def self.database
      @database ||= YAML.load_file("#{root}/config/database.yml").fetch(environment)
    end

    def self.redis
      @redis ||= YAML.load_file("#{root}/config/redis.yml").fetch(environment).symbolize_keys
    end

    def self.revision
      @revision ||= (
        file_path = "#{root}/REVISION"
        File.read(file_path) if File.exists?(file_path)
      )
    end
  end
end
