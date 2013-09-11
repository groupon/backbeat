require_relative 'base'
module Service
  class BackbeatClient < Base
    post /(activity|decision|notification)/ do |env|
      p " HTTP Request sent to client to make #{env['PATH_INFO']}"
      [200, {}, []]
    end
  end
end