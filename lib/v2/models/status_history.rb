class V2::StatusHistory < ActiveRecord::Base
  self.primary_key = 'id'
  belongs_to :node
end
