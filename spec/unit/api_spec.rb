require 'spec_helper'

describe Api::App do
  Api::App.routes.each do |route|
    it "service discovery documentation for #{route.route_path}" do
      options = route.instance_variable_get(:@options)
      options.keys.should include(:action_descriptor)
    end
  end
end
