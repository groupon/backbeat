module WorkflowServer
  module AsyncClient

    def self.perform_activity(id)
      #self.parent::AccountingServiceClient.ActivityWorker.enqueue(id)
    end

    def self.make_decision(decider_klass, id, subject_type, subject_id)
      #self.parent::AccountingServiceClient.DecisionWorker.enqueue(decider_klass, id, subject_type, subject_id)
    end

  end
end