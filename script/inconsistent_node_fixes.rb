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

# NOTE:
# This is not a script meant to run all at once.
# These are separate scenarios in which nodes may become stuck.
# Run one fix at a time, then check the counts.

time = Time.now - 20.hours

# For checking inconsistent nodes
Backbeat::Node
  .where("fires_at < ?", time)
  .where("(current_server_status <> 'complete' OR current_client_status <> 'complete') AND current_server_status <> 'deactivated'")
  .count

Backbeat::Node
  .where(current_server_status: :processing_children, current_client_status: :complete)
  .where("fires_at < ?", time)
  .each { |n| Backbeat::Events::ScheduleNextNode.call(n) }

Backbeat::Node
  .where("fires_at < ?", time)
  .where(current_server_status: :started, current_client_status: :ready)
  .each { |n| Backbeat::Events::StartNode.call(n) }

Backbeat::Node
  .where("fires_at < ?", time)
  .where(current_server_status: :sent_to_client, current_client_status: :received)
  .each { |n| Backbeat::Events::ScheduleNextNode.call(n.parent) }

Backbeat::Node
  .where(current_server_status: :sent_to_client, current_client_status: :received)
  .where("fires_at < ?", time)
  .each { |n| Backbeat::Client.perform(n) if n.children.count == 0 }

Backbeat::Node
  .where("fires_at < ?", time)
  .where(current_server_status: :ready, current_client_status: :ready)
  .each { |n| Backbeat::Events::ScheduleNextNode.call(n.parent) }
