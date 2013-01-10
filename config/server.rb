# Set the mongo config
require 'mongoid'
mongo_path = File.expand_path(File.join(__FILE__, "..", "mongoid.yml"))
Mongoid.load!(mongo_path, Goliath.env || :development)

environment :production do
end

environment :development do
end

environment :test do
end