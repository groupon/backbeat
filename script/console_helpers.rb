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

def establish_readonly_connection
  ActiveRecord::Base.class_eval do
    def readonly?; true; end
  end
  IRB.CurrentContext.irb_name = "[PROD-RO]"
  readonly_db_config = YAML::load_file("#{File.dirname(__FILE__)}/../config/database.yml")["production_readonly"]
  if readonly_db_config
    ActiveRecord::Base.establish_connection(readonly_db_config)
    ActiveRecord::Base.connection.reset!
  else
    raise "No production readonly database defined in database.yml"
  end
end

def establish_write_connection
  ActiveRecord::Base.class_eval do
    def readonly?; false; end
  end
  IRB.CurrentContext.irb_name = "irb"
  default_db_config = YAML::load_file("#{File.dirname(__FILE__)}/../config/database.yml")[Backbeat::Config.environment]
  ActiveRecord::Base.establish_connection(default_db_config)
  ActiveRecord::Base.connection.reset!
end

# prints running workers counted by queue and host
def sidekiq_job_count
  Sidekiq::Workers.new.group_by do |conn|
    conn.first.split(":")[0] + " " + conn.third["queue"]
  end.each_pair { |name, conns| puts "#{name} - #{conns.count}" }
  nil
end

def system_status(options = {})
  range = options[:range] || { lower_bound: 24.hours.ago, upper_bound: Time.now }
  status = options[:status]
  workflow_names = options[:workflow_names]
  activity_names = options[:activity_names]
  omit_regex = options[:omit]

  nodes_arel = Node.where('nodes.fires_at > ?', range[:lower_bound]).where('nodes.fires_at < ?', range[:upper_bound]).joins(:workflow).reorder("")
  nodes_arel = nodes_arel.where(current_client_status: status) if status
  nodes_arel = nodes_arel.where("workflows.name" => workflow_names) if workflow_names
  nodes_arel = nodes_arel.where(name: activity_names) if activity_names
  count_arel = nodes_arel.group("nodes.name, wf_name, nodes.current_client_status").select("COUNT(nodes.name) AS node_count, nodes.name, nodes.current_client_status, workflows.name AS wf_name")

  count_hash = Hash.new{|h,k| h[k] = Hash.new{|h,k| h[k] = Hash.new{|h,k| h[k] = 0}}}

  count_arel.each do |activity|
    unless activity.name =~ omit_regex
      count_hash[activity.current_client_status][activity.wf_name][activity.name] += activity.node_count
    end
  end
  print_table(count_hash)
  count_hash
end

def print_table(count_hash)
  wf_width = 50
  activity_width = 80
  border_width = 160
  border = "-"*border_width
  piping = "-"*border_width + '|'
  puts border
  puts("System status")
  puts border
  count_hash.each do |status, workflows|
    puts("Status: " + status.upcase)
    puts piping
    workflows.each do |wf_name, activities|
      puts(wf_name.rjust(wf_width) + ' |'.rjust(border_width - wf_width + 1))
      puts piping
      puts "Activities".ljust(activity_width) + "Count\n\n"
      activities.sort_by{ |a| a.first.downcase }.each do |activity_name, count|
        puts(activity_name.ljust(activity_width) + count.to_s)
      end
      puts piping
    end
  end
end

module Backbeat
  module ConsoleHelpers
    EVENT_MAP = {
      start: Events::StartNode,
      retry: Events::RetryNode,
      deactivate: Events::DeactivatePreviousNodes,
      reset: Events::ResetNode
    }

    EVENT_MAP.each do |method_name, event|
      define_method(method_name) do
        event.call(self)
      end
    end
  end

  class Node
    include ConsoleHelpers
  end
end
