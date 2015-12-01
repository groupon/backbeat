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

module Backbeat
  module Client
    module HashKeyTransformations
      def self.camelize_keys(object)
        transform_keys(object) do |key|
          key.to_s.camelize(:lower).to_sym
        end
      end

      def self.underscore_keys(object)
        transform_keys(object) do |key|
          key.to_s.underscore.to_sym
        end
      end

      def self.transform_keys(object, &block)
        case object
        when Hash
          object.reduce({}) do |memo, (key, value)|
            new_key = block.call(key)
            memo[new_key] = transform_keys(value, &block)
            memo
          end
        when Array
          object.map do |value|
            transform_keys(value, &block)
          end
        when ActiveRecord::Base
          transform_keys(object.attributes, &block)
        when ActiveRecord::Relation
          transform_keys(object.to_a, &block)
        else
          if object.respond_to?(:to_hash)
            transform_keys(object.to_hash, &block)
          else
            object
          end
        end
      end
    end
  end
end
