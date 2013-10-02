require 'external_service'
module Service
  class BackbeatClient < ExternalService::Base
    post /(activity|decision|notification)/ do |env|
      p " HTTP Request sent to client to make #{env['PATH_INFO']}"
      [200, {}, []]
    end
  end
end