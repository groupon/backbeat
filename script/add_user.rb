require File.expand_path('../../config/environment',  __FILE__)
require 'logger'

user_id = ENV['BACKBEAT_USER_ID']
client_url = ENV['BACKBEAT_CLIENT_URL']
logger = Logger.new(STDOUT)

if user_id
  logger.info "Looking for user with id: #{user_id}"
  user = Backbeat::User.where(id: user_id).first

  if user
    logger.info "User exists: "
  else
    user = Backbeat::User.new(
      decision_endpoint:     "#{client_url}/activity",
      activity_endpoint:     "#{client_url}/activity",
      notification_endpoint: "#{client_url}/notification"
    )
    user.id = user_id
    user.save!

    logger.info "Created new user with id #{user.id}. Attributes:"
  end

  user.attributes.each do |attr, val|
    logger.info "#{attr}: #{val}"
  end
else
  logger.info "No user provided"
end
