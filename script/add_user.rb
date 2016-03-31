# Copyright (c) 2015, Groupon, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# Neither the name of GROUPON nor the names of its contributors may be
# used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require File.expand_path('../../config/environment',  __FILE__)
require 'logger'

user_id = ENV['BACKBEAT_USER_ID']
client_url = ENV['BACKBEAT_CLIENT_URL']
name =  ENV['BACKBEAT_USER_NAME']

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
      notification_endpoint: "#{client_url}/notification",
      name: name
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
