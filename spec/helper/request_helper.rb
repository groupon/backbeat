module RequestHelper
  def activity_hash(activity_node, attributes = {})
    Backbeat::Client::HashKeyTransformations.camelize_keys(
      { "activity" => Backbeat::Client::NodeSerializer.call(activity_node).merge(attributes) }
    ).to_json
  end

  def decision_hash(decision_node, attributes = {})
    Backbeat::Client::HashKeyTransformations.camelize_keys(
      { "decision" => Backbeat::Client::NodeSerializer.call(decision_node).merge(attributes) }
    ).to_json
  end
end
