module WorkflowServer
  module Models
    class Watchdog
      include Mongoid::Document
      include Mongoid::Timestamps

      field :name, type: Symbol
      field :starves_in, type: Integer, default: 10.minutes
      field :subject_klass, type: String
      field :subject_id, type: String

      index({ name: 1, subject_klass: 1, subject_id: 1 }, { unique: true })

      belongs_to :timer, class_name: "Delayed::Backend::Mongoid::Job", inverse_of: nil

      validates_presence_of :name, :subject_id, :subject_klass

      before_destroy do
        timer.destroy if timer
      end

      def self.start(subject, name = :timeout, starves_in = 10.minutes)
        Watchdog.kill(subject,name)
        new_dog = create!(name: name,
                          starves_in: starves_in,
                          subject_klass: subject.class.to_s,
                          subject_id: subject.id)
        new_dog.timer = Delayed::Backend::Mongoid::Job.enqueue(new_dog, run_at: new_dog.starves_in.from_now)
        new_dog.save!
        new_dog
      end

      alias_method :stop, :destroy
      alias_method :kill, :destroy
      alias_method :dismiss, :destroy

      def feed
        timer.destroy if timer
        timer = Delayed::Backend::Mongoid::Job.enqueue(self, run_at: starves_in.from_now)
        save!
      end
      alias_method :kick, :feed
      alias_method :pet, :feed
      alias_method :wake, :feed

      def subject
        subject_klass.constantize.find(subject_id)
      end

      def perform
        subject.timeout(TimeOut.new("#{name}"))
        destroy
      end

      class << self
        def feed(subject, name = :timeout)
          dog = Watchdog.where(subject_klass: subject.class.to_s, subject_id: subject.id, name: name).first
          if dog
            dog.feed
          else
            Watchdog.start(subject,name)
          end
        end
        alias_method :kick, :feed
        alias_method :pet, :feed
        alias_method :wake, :feed


        def stop(subject, name = :timeout)
          dog = Watchdog.where(subject_klass: subject.class.to_s, subject_id: subject.id, name: name).first
          dog.stop if dog
        end
        alias_method :kill, :stop
        alias_method :dismiss, :stop

        def mass_stop(subject)
          Watchdog.destroy_all(subject_klass: subject.class.to_s, subject_id: subject.id)
        end
        alias_method :mass_kill, :mass_stop
        alias_method :mass_dismiss, :mass_stop

      end

    end
  end
end
