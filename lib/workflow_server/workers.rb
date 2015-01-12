module WorkflowServer
  module Workers
    require_relative  'workers/sidekiq_job_worker'
    require_relative  'workers/v2_sidekiq_worker'
  end
end
