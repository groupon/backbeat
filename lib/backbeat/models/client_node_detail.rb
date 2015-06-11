module Backbeat
  class ClientNodeDetail < ActiveRecord::Base
    belongs_to :node

    serialize :metadata, JSON
    serialize :data, JSON
    serialize :result, JSON
  end
end
