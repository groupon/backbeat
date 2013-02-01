module WorkflowServer
  class Config
    def self.environment
      @environment ||= get_environment.to_sym
    end

    def self.root
      @root ||= get_root
    end

    def self.log_file
      ENV['LOG_FILE'] || WorkflowServer::Config.options[:log] || "/tmp/test.log"
    end

    def self.options
      @options ||= HashWithIndifferentAccess.new(YAML.load(File.read(File.join(root, "config", "options.yml"))))[environment]
    end

    def self.option(field)
      options[field]
    end

    def self.get_environment
      hostname = `hostname`.chomp

      if ENV['RACK_ENV']
        return ENV['RACK_ENV']
      end
      ENV['RACK_ENV'] = if hostname.match /accounting/
        case hostname
        when /uat/, /fed2-tat/
          'uat'
        when /staging/, /fed1-tat/
          'staging'
        else
          'production'
        end
      else
        'development'
      end
    end

    def self.get_root
      case environment
      when :test, :development
        File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
      else
        "/var/groupon/backbeat/current"
      end
    end
  end
end