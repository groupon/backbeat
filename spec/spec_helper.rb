$: << File.expand_path(File.join(__FILE__, "../.."))

ENV['RACK_ENV'] = "test"

require 'bundler'

Bundler.setup
Bundler.require(:default, :test)

require 'server'
require 'goliath/test_helper'

FactoryGirl.find_definitions

RSpec.configuration.before(:each) do
  #Mongoid::Sessions.default.collections.select {|c| c.name !~ /system/ }.each(&:drop)
end

RSpec.configuration.after(:each) do
  Mongoid::Sessions.default.collections.select {|c| c.name !~ /system/ }.each(&:drop)
end

RSpec.configuration.after(:suite) do
  Mongoid::Sessions.default.collections.select {|c| c.name !~ /system/ }.each(&:drop)
end

RSpec.configure do |config|
  # Use color in STDOUT
  config.color_enabled = true

  # Use the specified formatter
  config.formatter = :documentation # :progress, :html, :textmate
end