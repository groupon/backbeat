# NOTE:
# This is not a script meant to run all at once.
# These are separate scenarios in which nodes may become stuck.
# Run one fix at a time, then check the counts.

time = Time.now - 20.hours

# For checking inconsistent nodes
Backbeat::Node
  .where("fires_at < ?", time)
  .where("(current_server_status <> 'complete' OR current_client_status <> 'complete') AND current_server_status <> 'deactivated'")
  .count

Backbeat::Node
  .where(current_server_status: :processing_children, current_client_status: :complete)
  .where("fires_at < ?", time)
  .each { |n| Backbeat::Events::ScheduleNextNode.call(n) }

Backbeat::Node
  .where("fires_at < ?", time)
  .where(current_server_status: :started, current_client_status: :ready)
  .each { |n| Backbeat::Events::StartNode.call(n) }

Backbeat::Node
  .where("fires_at < ?", time)
  .where(current_server_status: :sent_to_client, current_client_status: :received)
  .each { |n| Backbeat::Events::ScheduleNextNode.call(n.parent) }

Backbeat::Node
  .where(current_server_status: :sent_to_client, current_client_status: :received)
  .where("fires_at < ?", time)
  .each { |n| Backbeat::Client.perform(n) if n.children.count == 0 }

Backbeat::Node
  .where("fires_at < ?", time)
  .where(current_server_status: :ready, current_client_status: :ready)
  .each { |n| Backbeat::Events::ScheduleNextNode.call(n.parent) }
