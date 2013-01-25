module WorkflowServer
  class Config
    def self.environment
      @environment ||= get_environment.to_sym
    end

    def self.root
      @root ||= get_root
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
        ENV['RACK_ENV']
      elsif hostname.match /accounting/
        case hostname
        when /uat/
          'uat'
        when /staging/
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