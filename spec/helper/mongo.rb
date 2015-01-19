module Helper
  class Mongo
    def self.start(port)
      mongo = self.new(port)
      mongo.start
    end

    def self.stop(port)
      mongo = self.new(port)
      mongo.stop
    end

    attr_reader :port

    def initialize(port = 27017)
      @port = port
    end

    def start
      delete_directory(root_dir)
      ensure_directory(root_dir)
      ensure_directory(db_dir)
      ensure_directory(log_dir)
      system("mongod --dbpath #{db_dir} --logpath #{log_dir}/mongo.log --port #{port} --pidfilepath #{pidfile} --fork")
    end

    def stop
      signal("TERM")
      delete_directory(root_dir)
    end

    private

    def ensure_directory(dir)
      FileUtils.mkdir_p(dir) unless File.exist?(dir)
    end

    def delete_directory(dir)
      FileUtils.rm_rf(dir) unless !File.exist?(dir)
    end

    def signal(signal)
      process_id = File.readable?(pidfile) ? File.read(pidfile).to_i : nil
      begin
        process_id.nil? ? false : Process.kill(signal, process_id) and true
      rescue Errno::ESRCH
        # We must have a stale pidfile, remove it.
        File.delete(pidfile) if File.exist?(pidfile)
        false
      end
    end

    def root_dir
      File.expand_path(File.join(__FILE__, "..", "..", "data", "mongo-#{self.port}"))
    end

    def db_dir
      "#{root_dir}/db"
    end

    def log_dir
      "#{root_dir}/logs"
    end

    def pidfile
      "#{root_dir}/mongo.pid"
    end
  end
end
