require 'monitor'
require 'rack'
require 'webrick'

#
# ExternalService::Base creates a simple rack application that records all
# the incoming http requests, and runs inside a background thread
#
# Example
#
# order_service = Accounting::Utility::ExternalService::Base.new('order_service')
# order_service.start(4000) #=> "http://localhost:4000"
# 
# Accounting::Utility::Http::Client.get("http://localhost:4000") => <Accounting::Utility::Http::Response:0x007fdba38c0e70 @response=#<Net::HTTPOK 200 OK  readbody=true>, @headers={"content-type"=>["application/json"], "server"=>["WEBrick/1.3.1 (Ruby/1.9.3/2012-02-16)"], "date"=>["Sun, 14 Oct 2012 01:04:04 GMT"], "content-length"=>["0"], "connection"=>["close"]}>>
#
# order_service.requests => [{"GATEWAY_INTERFACE"=>"CGI/1.1", "PATH_INFO"=>"/", "QUERY_STRING"=>"", "REMOTE_ADDR"=>"::1", "REMOTE_HOST"=>"localhost", "REQUEST_METHOD"=>"GET", "REQUEST_URI"=>"http://localhost:4000/", "SCRIPT_NAME"=>"", "SERVER_NAME"=>"localhost", "SERVER_PORT"=>"4000", "SERVER_PROTOCOL"=>"HTTP/1.1", "SERVER_SOFTWARE"=>"WEBrick/1.3.1 (Ruby/1.9.3/2012-02-16)", "HTTP_CONNECTION"=>"close", "HTTP_HOST"=>"localhost:4000", "rack.version"=>[1, 1], "rack.input"=>#<StringIO:0x007fdba39db9b8>, "rack.errors"=>#<IO:<STDERR>>, "rack.multithread"=>true, "rack.multiprocess"=>false, "rack.run_once"=>false, "rack.url_scheme"=>"http", "HTTP_VERSION"=>"HTTP/1.1", "REQUEST_PATH"=>"/"}]
#
# order_service.stop
#
# The default behavior returns an empty body. Customize it by adding a subclass that overrides the service method. You can inspect
# the environment passed and return different responses based on the type of request. 
# 
#
module Service
  class Base

    def initialize(name = nil)
      @name = name || self.class.name
      @thread = nil
      @server = nil
      @requests = []
      @requests.extend(MonitorMixin)
    end

    # sub-classes are expected to override this method and return an array with
    # three things [status, headers, body]
    def service(env)
      blocks = self.class.registered_blocks(env['REQUEST_METHOD'], env['PATH_INFO'])
      unless blocks.empty?
        blocks.map {|b| b.call(env) }.first
      else
        [404, {}, []]
      end
    end

    def start(port = 3000, range = 5)
      raise "Server running" if @thread.try(:alive?)
      monitor = Monitor.new
      status = nil
      clear
      @thread = Thread.new(@name) do
        max_port = port + range
        while port <= max_port
          begin
            ::Rack::Handler::WEBrick.run(app, :Port => port) do |server|
              puts "Server on port #{port}"
              @server = server
              monitor.synchronize { status = "http://localhost:#{port}"}
            end
            break unless status.nil?
          rescue => e
            status = "exception #{e}" if port == max_port
          ensure
            port += 1
          end
        end
      end
      while monitor.synchronize { status.nil? }
      end
      status
    end

    def stop
      @server.try(:shutdown)
      @server = nil
      @thread.try(:exit)
      @thread = nil
    end

    def requests
      @requests.synchronize do
        @requests.dup
      end
    end

    def clear
      old_requests = nil
      @requests.synchronize do
        old_requests = @requests.dup
        @requests.clear
      end
      old_requests
    end

    def running?
      @thread.try(:alive?) || false
    end

    def app
      lambda do |env|
        @requests.synchronize do
          @requests.push(env)
        end
        service(env)
      end
    end

    # For registering url's
    [:get, :post].each do |method|
      define_singleton_method(method) do |pattern, &block|
        register(method, pattern, &block)
      end
    end

    def self.register(method, pattern, &block)
      method_hash = instance_variable_get("@#{method.downcase}".to_sym) || {}
      method_hash[pattern] = block
      instance_variable_set("@#{method.downcase}", method_hash)
    end

    def self.registered_blocks(method, path_info)
      blocks = []
      method_hash = instance_variable_get("@#{method.downcase}".to_sym) || {}
      method_hash.each_pair do |pattern, block|
        if pattern.match path_info
          blocks.push(block)              
        end
      end
      blocks
    end
  end
end