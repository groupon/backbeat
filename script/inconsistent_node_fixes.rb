#NOTE this is not a script meant to run all at once. these are separate scenarios in which nodes may become stuck.

#Run one fix at a time, then check the counts.

time = Time.now - 20.hours

#For checking inconsistent nodes
V2::Node.where("fires_at < ?", time).where("(current_server_status <> 'complete' OR current_client_status <> 'complete') AND current_server_status <> 'deactivated'").count

nodes = V2::Node.where(current_server_status: :processing_children, current_client_status: :complete).where("fires_at < ?", time);1
nodes.each do |n|
  V2::Events::ScheduleNextNode.call(n)
end

nodes = V2::Node.where("fires_at < ?", time).where(current_server_status: :started, current_client_status: :ready);1
nodes.each do |n|
  V2::Events::StartNode.call(n)
end

nodes = V2::Node.where("fires_at < ?", time).where(current_server_status: :sent_to_client, current_client_status: :received);1
nodes.each do |n|
  V2::Events::ScheduleNextNode.call(n.parent)
end

nodes = V2::Node.where(current_server_status: :sent_to_client, current_client_status: :received).where("fires_at < ?", time);1
nodes.each do |n|
  if n.children.count == 0
    V2::Client.perform_action(n)
  end
end

nodes = V2::Node.where("fires_at < ?", time).where(current_server_status: :ready, current_client_status: :ready);1
nodes.each do |n|
  V2::Events::ScheduleNextNode.call(n.parent)
end
