class V2::NodeDetail < ActiveRecord::Base
  self.primary_key = 'id'
  belongs_to :node
end
