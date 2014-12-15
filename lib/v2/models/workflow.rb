class V2::Workflow < ActiveRecord::Base
  self.primary_key = 'id'
  belongs_to :user
  has_many :nodes
  serialize :subject, JSON

  def serializable_hash(options = {})
    self.attributes
  end
end
