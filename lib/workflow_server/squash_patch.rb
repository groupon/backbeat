require 'squash/ruby'

module Squash
  module Ruby
    def self.http_transmit(url, headers, body)
      response = ::HTTParty.post(url, body: body, headers: {'Content-Type' => 'application/json'}.merge(headers))
      if response.code.between?(200, 299)
        return true
      else
        self.failsafe_log 'http_transmit', "Response from server: #{response.code}"
        return false
      end
    end
  end
end
