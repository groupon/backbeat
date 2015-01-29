class V2::ClientNodeDetail < ActiveRecord::Base
  belongs_to :node

  serialize :metadata, JSON
  serialize :data, JSON
  serialize :result, JSON
end
