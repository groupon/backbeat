# coding: utf-8
lib = File.expand_path("../lib", __FILE__)

$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "backbeat/version"

Gem::Specification.new do |spec|
  spec.name          = "backbeat-server"
  spec.version       = Backbeat::VERSION
  spec.authors       = ["Carl Thuringer"]
  spec.email         = ["carl@groupon.com"]

  spec.summary       = %Q{Orchestate on the Backbeat.}
  spec.description   = %Q{This is the server application for Backbeat, the open-source workflow service by Groupon. For more information on what Backbeat is, and documentation for using Backbeat, see the [wiki](https://github.com/groupon/backbeat/wiki).}
  spec.homepage      = "https://github.com/groupon/backbeat"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "rake", "~> 11.1.2"
  spec.add_runtime_dependency "grape", "~> 0.13.0"
  spec.add_runtime_dependency "puma", "~> 2.13.4"
  # spec.add_runtime_dependency "jruby-openssl"
  spec.add_runtime_dependency "activerecord", "~> 4.1.0"
  spec.add_runtime_dependency "sidekiq", "~> 3.5.0"
  spec.add_runtime_dependency "sidekiq_schedulable", "~> 0.0.3"
  spec.add_runtime_dependency "httparty", "~> 0.13.7"
  spec.add_runtime_dependency "sidekiq-failures", "~> 0.4.0"
  spec.add_runtime_dependency "mail", "~> 2.6.4"
  spec.add_runtime_dependency "enumerize", "~> 1.1.1"
  spec.add_runtime_dependency "activerecord-postgresql-adapter", "~> 0.0.1"
  spec.add_runtime_dependency "redis-activesupport", "~> 4.1.0"
  spec.add_runtime_dependency "sinatra", "~> 1.4.7"

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "pry", "~> 0.10.3"

end
