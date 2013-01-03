module WorkflowServer
  module Models
    class Watchdog
      include Mongoid::Document

      field :name, type: Symbol
      field :starves_at, type: Integer
      field :subject_type, type: String
      field :subject_id, type: String

      index({ name: 1, subject_type: 1, subject_id: 1 }, { unique: true })

      belongs_to :timer, class_name: "Delayed::Backend::Mongoid::Job", inverse_of: nil

      validates_presence_of :name, :subject_id, :subject_type

      def self.start(subject, name = :timeout, starves_at = 10.minutes)
        new_dog = create!(name: name,
                          starves_at: starves_at,
                          subject_type: subject.class.to_s,
                          subject_id: subject.id)
        new_dog.timer = Delayed::Backend::Mongoid::Job.enqueue(new_dog, run_at: new_dog.starves_at.from_now)
        new_dog.save!
        new_dog
      end

      def stop
        timer.delete if timer
        delete
      end
      alias_method :kill, :stop

      def feed
        timer.delete if timer
        timer = Delayed::Backend::Mongoid::Job.enqueue(self, run_at: starves_at.from_now)
        save!
      end
      alias_method :kick, :feed
      alias_method :pet, :feed
      alias_method :wake, :feed

      def subject
        subject_type.constantize.find(subject_id)
      end

      def perform
        subject.timeout(name)
        delete
      end

      class << self
        def feed(subject, name = :timeout)
          dog = Watchdog.where(subject_type: subject.class.to_s, subject_id: subject.id, name: name).first
          dog.feed
        end
        alias_method :kick, :feed
        alias_method :pet, :feed
        alias_method :wake, :feed


        def stop(subject, name = :timeout)
          dog = Watchdog.where(subject_type: subject.class.to_s, subject_id: subject.id, name: name).first
          dog.stop
        end
        alias_method :kill, :stop
      end

    end
  end
end
