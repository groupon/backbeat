require 'rubygems'
require 'bundler/setup'

$: << File.expand_path(File.join(__FILE__, "..", "lib"))

require 'grape'
require 'awesome_print'
require 'mongoid'
require 'mongoid-locker'
require 'delayed_job_mongoid'
require 'tree'
require 'mongoid_indifferent_access'
require 'uuid'
require 'log4r'
require 'api'