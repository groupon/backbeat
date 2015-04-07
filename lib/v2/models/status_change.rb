class V2::StatusChange < ActiveRecord::Base
  belongs_to :node
  default_scope { order("id asc") }
end
