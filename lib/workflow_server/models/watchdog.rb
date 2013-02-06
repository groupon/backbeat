module WorkflowServer
  module Models
    class Watchdog
      include Mongoid::Document
      include Mongoid::Timestamps

      field :name, type: Symbol
      field :starves_in, type: Integer, default: 10.minutes

      belongs_to :subject, inverse_of: :watchdogs, class_name: "WorkflowServer::Models::Event", index: true
      belongs_to :timer, class_name: "Delayed::Backend::Mongoid::Job", inverse_of: nil, dependent: :destroy

      index({ name: 1, subject: 1}, { unique: true })

      validates_presence_of :name, :subject

      before_destroy do
        self.timer.destroy if self.timer
      end

      def feed
        self.timer.destroy if self.timer
        self.timer = Delayed::Backend::Mongoid::Job.enqueue(self, run_at: starves_in.from_now)
        save!
      end
      alias_method :kick, :feed
      alias_method :pet, :feed
      alias_method :wake, :feed

      alias_method :dismiss, :destroy
      alias_method :stop, :destroy
      alias_method :kill, :destroy

      def perform
        self.subject.timeout(TimeOut.new("#{name}"))
        destroy
      end

      class << self
        def start(subject, name = :timeout, starves_in = 10.minutes)
          Watchdog.dismiss(subject,name)
          new_dog = create!(name: name,
                            starves_in: starves_in,
                            subject: subject)
          new_dog.timer = Delayed::Backend::Mongoid::Job.enqueue(new_dog, run_at: new_dog.starves_in.from_now)
          new_dog.save!
          new_dog
        end

        def feed(subject, name = :timeout)
          dog = Watchdog.where(subject: subject, name: name).first
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
          Watchdog.destroy_all(subject: subject, name: name)
        end

        alias_method :dismiss, :stop
        alias_method :kill, :stop

        def mass_stop(subject)
          Watchdog.destroy_all(subject: subject)
        end

        alias_method :mass_dismiss, :mass_stop
        alias_method :mass_kill, :mass_stop
      end

    end
  end
end
