require_relative 'models'

module WorkflowServer
  class Manager
    class << self

      def schedule_next_decision(workflow)
        workflow.with_lock do
          unless Models::Decision.where(workflow: workflow).not_in(:status => [:complete, :open]).any?
            if (next_decision = Models::Decision.where(workflow: workflow, status: :open).first)
              next_decision.start
            end
          end
        end
      end

      def get_event(id)
        Models::Event.find(id)
      end

      # options include workflow_type: workflow_type, subject_klass: subject_klass, subject_id: subject_id, decider: decider, name: workflow_type, user: user
      def find_or_create_workflow(options = {})
        method_options = options.dup
        method_options[:name] ||= method_options[:workflow_type]
        workflow = Models::Workflow.find_or_create_by(workflow_type: method_options.delete(:workflow_type),
                                                      subject_klass: method_options.delete(:subject_klass),
                                                      subject_id: method_options.delete(:subject_id),
                                                      decider: method_options.delete(:decider),
                                                      name: method_options.delete(:name),
                                                      user: method_options.delete(:user))
        workflow.save
        workflow
      end
    end
  end
end