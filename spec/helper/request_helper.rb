module RequestHelper
  def activity_hash(activity_node)
    {
      "activity" => {
        "id" => activity_node.id,
        "mode" => activity_node.mode,
        "name" => activity_node.name,
        "parentId" => activity_node.parent_id,
        "workflowId" => activity_node.workflow_id,
        "userId" => activity_node.user_id,
        "clientData" => {
          "could" => "be",
          "any" => "thing"
        }
      }
    }
  end
end
