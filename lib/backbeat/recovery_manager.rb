module Backbeat
  class RecoveryManager

    def self.run
      # collect client and server inconsistencies
      # notify
      # autoheal based on settings
    end

    def self.client_inconsistencies
      Backbeat::Node.where(current_server_status: :sent_to_client).joins(:node_detail).merge(NodeDetail.where(complete_by: 1.week.ago..Time.now))
    end

    def self.server_inconsistencies
      Backbeat::Node.where("fires_at < ?", THRESHOLD_TIME).active.incomplete.where("current_server_status <> 'sent_to_client'")
    end
  end
end
