class V2::Node < ActiveRecord::Base
  self.primary_key = 'id'
  belongs_to :workflow
  belongs_to :user
  has_many :children,  class_name: "V2::User", foreign_key: "parent_id"
  belongs_to :parent, inverse_of: :children
end
