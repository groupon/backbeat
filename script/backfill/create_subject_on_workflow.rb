#assumes subject is not on the document
WorkflowServer::Models::Workflow.field :subject, type: Hash, default: {}
WorkflowServer::Models::Workflow.each do |wf|
  wf.subject = { subject_id: wf.subject_id.to_s, subject_klass: wf.subject_klass }
  wf.save!
end
