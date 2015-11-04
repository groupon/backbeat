require File.expand_path('../../config/environment',  __FILE__)
require 'irb'
require 'redis-namespace'
require 'ap'
require_relative 'console_helpers'

include Backbeat

ActiveRecord::Base.logger = Logger.new(STDOUT)
ARGV.clear
IRB.start
