class V2::StatusChange < ActiveRecord::Base
  self.primary_key = 'id'
  belongs_to :node
end
