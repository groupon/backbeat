class V2::StatusChange < ActiveRecord::Base
  include UUIDSupport

  uuid_column :uuid

  belongs_to :node
end
