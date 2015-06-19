require File.expand_path('../config/environment',  __FILE__)

require 'backbeat/web'

run Backbeat::Web::App
