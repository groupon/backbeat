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

require 'backbeat/workflow_tree/colorize'

module Backbeat
  class WorkflowTree
    def self.to_hash(node)
      new(node).to_hash
    end

    def self.to_string(node)
      new(node).to_string
    end

    def initialize(root)
      @root = root
    end

    def traverse(options = {}, &block)
      _traverse(root, options, &block)
    end

    def to_hash(node = root)
      {
        id: node.id.to_s,
        name: node.name,
        user_id: node.user_id,
        subject: node.subject,
        mode: node.is_a?(Node) ? node.mode : nil,
        current_server_status: node.is_a?(Node) ? node.current_server_status : nil,
        current_client_status: node.is_a?(Node) ? node.current_client_status : nil,
        children: children(node).map { |child| to_hash(child) }
      }
    end

    def to_string(node = root, depth = 0)
      child_strings = children(node).map do |child|
        to_string(child, depth + 1)
      end.join

      NodeString.build(node, depth) + child_strings
    end

    private

    attr_reader :root

    def _traverse(node, options, &block)
      block.call(node) if options.fetch(:root, true)
      children(node).each do |child|
        _traverse(child, options.merge(root: true), &block)
      end
    end

    def children(node)
      parent_id = node.is_a?(Node) ? node.id : nil
      tree[parent_id] || []
    end

    def tree
      @tree ||= Node.where(
        workflow_id: root.workflow_id
      ).group_by(&:parent_id)
    end

    class NodeString
      include Colorize

      def self.build(node, depth)
        new(node, depth).build
      end

      def initialize(node, depth)
        @node = node
        @depth = depth
      end

      def build
        "\n#{node.id.to_s}#{spacer}#{node_display}"
      end

      private

      attr_reader :node, :depth

      def spacer
        cyan("#{('   ' * depth)}\|--")
      end

      def node_display
        if node.is_a?(Node)
          colorize_details(
            "#{node.name} - "\
            "server: #{node.current_server_status}, "\
            "client: #{node.current_client_status}"
          )
        else
          node.name
        end
      end

      def colorize_details(node_details)
        statuses = [node.current_server_status.to_sym, node.current_client_status.to_sym]
        case
        when statuses.include?(:errored)
          red(node_details)
        when statuses.all?{|s| s == :ready}
          white(node_details)
        when statuses.all?{|s| s == :complete}
          green(node_details)
        when statuses.include?(:deactivated)
          white(node_details)
        else
          yellow(node_details)
        end
      end
    end
  end
end
