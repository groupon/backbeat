module RequestHelper
  def activity_hash(activity_node, attributes = {})
    WorkflowServer::Helper::HashKeyTransformations.camelize_keys(
      { "activity" => V2::Client::NodeSerializer.call(activity_node).merge(attributes) }
    ).to_json
  end

  def decision_hash(decision_node, attributes = {})
    WorkflowServer::Helper::HashKeyTransformations.camelize_keys(
      { "decision" => V2::Client::NodeSerializer.call(decision_node).merge(attributes) }
    ).to_json
  end
end
