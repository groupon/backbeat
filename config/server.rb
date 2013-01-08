require 'mongoid'
mongo_path = File.expand_path(File.join(__FILE__, "..", "mongoid.yml"))
Mongoid.load!(mongo_path, :development)