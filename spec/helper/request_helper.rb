module RequestHelper
  def activity_hash(activity_node)
    WorkflowServer::Helper::HashKeyTransformations.camelize_keys(
      { "activity" => V2::Client::NodeSerializer.call(activity_node) }
    ).to_json
  end

  def decision_hash(decision_node)
    WorkflowServer::Helper::HashKeyTransformations.camelize_keys(
      { "decision" => V2::Client::NodeSerializer.call(decision_node) }
    ).to_json
  end
end
