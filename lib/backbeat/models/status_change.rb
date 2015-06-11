module Backbeat
  class StatusChange < ActiveRecord::Base
    belongs_to :node
    default_scope { order("id asc") }
  end
end
