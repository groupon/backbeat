module WorkflowServer
  module Models
    class Workflow
      include Mongoid::Document
      include Mongoid::Timestamps
      include Mongoid::Locker

      field :workflow_type, type: Symbol
      field :subject_id, type: Integer
      field :subject_type, type: String
      field :decider, type: String

      index({ workflow_type: 1, subject_type: 1, subject_id: 1 }, { unique: true })

      has_many :events, order: {created_at: 1}

      validates_presence_of :workflow_type, :subject_id, :subject_type, :decider

      def signal(name)
        WorkflowServer::Models::Signal.create!(name: name, workflow: self)
      end

      {
        flags: Flag,
        decisions: Decision,
        signals: Signal,
        timers: Timer,
        activities: Activity
      }.each_pair do |name, klass|
        #
        # Returns events of the given type
        #
        define_method(name) do
          arel = events.type(klass.to_s)
          if block_given?
            arel.each do |record|
              yield record
            end
          else
            arel.all
          end
        end

        #
        # Returns events of a particular type in the past given the reference task
        #
        define_method("past_#{name}") do |task|
          arel = events.where(:created_at.lte => task.created_at, :id.ne => task.id).type(klass.to_s)
          if block_given?
            arel.each do |record|
              yield record
            end
          else
            arel.all
          end
        end
      end
    end
  end
end
