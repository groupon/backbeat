# -*- encoding: utf-8 -*-
require File.expand_path('../lib/workflow_server/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = "workflow_server"
  gem.description   = "the server side of a workflow utility for ruby"
  gem.authors       = ["FED"]
  gem.email         = ["fed@groupon.com"]
  gem.summary       = "someone should write this..."
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  gem.version       = WorkflowServer::VERSION


  gem.add_dependency 'mongoid'
  gem.add_dependency 'mongoid-locker'
  gem.add_dependency 'delayed_job_mongoid'
  gem.add_dependency 'rubytree'
end
