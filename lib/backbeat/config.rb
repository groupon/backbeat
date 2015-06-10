module Backbeat
  class Config
    def self.environment
      @environment ||= (
        env = ENV.fetch('RACK_ENV', 'development')
        env == 'test' ? 'development' : env
      )
    end

    def self.root
      @root ||= File.expand_path('../../../', __FILE__)
    end

    def self.log_file
      ENV['LOG_FILE'] || options[:log]
    end

    def self.options
      @options ||= options_yml[environment]
    end

    def self.options_yml
      options = YAML.load_file("#{root}/config/options.yml")
      options.default_proc = ->(h, k) { h.key?(k.to_s) ? h[k.to_s] : nil }
      options
    end

    def self.database
      @database ||= YAML.load_file("#{root}/config/database.yml")[environment.to_s]
    end

    def self.redis
      @redis ||= (
        config = YAML.load_file("#{root}/config/redis.yml")[environment.to_s]
        config['url'] = "redis://#{config['host']}:#{config['port']}"
        config
      )
    end
  end
end
