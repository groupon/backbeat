class V2::NodeDetail < ActiveRecord::Base
  self.primary_key = 'id'
  belongs_to :node

  serialize :valid_next_events, JSON

  before_create do
    self.retry_times_remaining ||= 4
    self.retry_interval ||= 20
  end
end
