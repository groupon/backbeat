class V2::ClientNodeDetail < ActiveRecord::Base
  include UUIDSupport
  belongs_to :node

  uuid_column :uuid
  serialize :metadata, JSON
  serialize :data, JSON
  serialize :result, JSON
end
