module Backbeat
  class Config
    def self.environment
      @environment ||= ENV.fetch('RACK_ENV', 'development')
    end

    def self.root
      @root ||= File.expand_path('../../../', __FILE__)
    end

    def self.log_file
      @log_file ||= ENV['LOG_FILE'] || options[:log]
    end

    def self.log_level
      @log_level ||= ::Logger.const_get(options[:log_level])
    end

    def self.options
      @options ||= (
        opts_yml = YAML.load_file("#{root}/config/options.yml")
        opts = opts_yml[environment]
        opts.default_proc = ->(h, k) { h.key?(k.to_s) ? h[k.to_s] : nil }
        opts
      )
    end

    def self.database
      @database ||= YAML.load_file("#{root}/config/database.yml")[environment.to_s]
    end

    def self.redis
      @redis ||= YAML.load_file("#{root}/config/redis.yml")[environment.to_s]
    end

    def self.revision
      @revision ||= (
        file_path = "#{root}/REVISION"
        File.read(file_path) if File.exists?(file_path)
      )
    end
  end
end
