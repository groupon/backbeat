class V2::Server

  def self.create_workflow(params, user)
    value = { workflow_type: params['workflow_type'],
              subject: params['subject'],
              decider: params['decider'],
              initial_signal: params['sinitial_signal'] || :start,
              user_id: user.id}
    unless workflow = V2::Workflow.where(subject:  params['subject'].to_json).first
      workflow = V2::Workflow.create!(value)
    end

    workflow
  end
end
