class V2::NodeDetail < ActiveRecord::Base
  self.primary_key = 'id'
  belongs_to :node

  validates :retries_remaining, numericality: { greater_than_or_equal_to: 0 }

  serialize :valid_next_events, JSON

  before_validation do
    self.retries_remaining ||= 4
    self.retry_interval ||= 20
  end
end
