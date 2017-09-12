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

require 'sidekiq'
require 'sidekiq-failures'

module Backbeat
  module Workers
    class AsyncWorker
      include Sidekiq::Worker
      include Logging
      extend Logging

      sidekiq_options retry: false, queue: Config.options[:async_queue]

      def self.find_job(event, node)
        Sidekiq::ScheduledSet.new.find do |job|
          event_name, node_data, options = job.item['args']
          event_name == event.name && node_data['node_id'] == node.id
        end
      end

      def self.remove_job(event, node)
        if job = find_job(event, node)
          job.delete
        end
      end

      def self.schedule_async_event(event, node, options)
        info(status: :schedule_async_event_started, node: node.id, event: event.name)
        node_data = { node_class: node.class.name, node_id: node.id }
        time = options.fetch(:time, Time.now)
        perform_at(time, event.name, node_data, options)
        info(status: :schedule_async_event_finished, node: node.id, event: event.name)
      end

      def perform(event_class, node_data, options)
        info(status: :perform_started, node_data: node_data, event: event_class, options: options)
        business_perform(event_class, node_data, options)
        info(status: :perform_finished, node: node_data, event: event_class)
      end

      private

      def business_perform(event_class, node_data, options)
        options = options.symbolize_keys
        node = deserialize_node(node_data)
        Server.fire_event(event_class.constantize, node, Schedulers::PerformEvent)
      rescue DeserializeError => e
        error(status: :deserialize_node_error, node: node_data["node_id"], error: e, backtrace: e.backtrace)
        raise e
      rescue NetworkError => e
        Kernel.sleep(Config.options[:connection_error_wait])
        if (node.reload.current_client_status != :complete)
          handle_processing_error(e, event_class, node, options)
        end
      rescue => e
        handle_processing_error(e, event_class, node, options)
      end

      def handle_processing_error(e, event_class, node, options)
        retries = options.fetch(:retries, 4)
        if retries > 0
          new_options = options.merge(retries: retries - 1, time: Time.now + 30.seconds)
          AsyncWorker.schedule_async_event(event_class.constantize, node, new_options)
        else
          info(status: :retries_exhausted, event_class: event_class, node: node.id, options: options, error: e, backtrace: e.backtrace)
          response = { error: { message: e.message } }
          Server.fire_event(Events::ServerError.new(response), node)
        end
      rescue => e
        error(status: :uncaught_exception, event_class: event_class, node: node.id, options: options, error: e, backtrace: e.backtrace)
        raise e
      end

      def deserialize_node(node_data)
        node_class = node_data["node_class"]
        node_id = node_data["node_id"]
        node_class.constantize.find(node_id)
      rescue => e
        raise DeserializeError.new(e.message)
      end
    end
  end
end
