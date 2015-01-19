class V2::ClientNodeDetail < ActiveRecord::Base
  self.primary_key = 'id'
  belongs_to :node

  serialize :metadata, JSON
  serialize :data, JSON
  serialize :result, JSON
end
