module FakeTorquebox
  VERSION = "0.0.1"

  def self.stub_jobs
    # this ideally should not be used (unit specs should always stub out publish calls)
    TorqueBox::Messaging::Queue.any_instance.stub(:publish)
  end

  def self.unstub_jobs
    TorqueBox::Messaging::Queue.any_instance.unstub(:publish)
  end

  def self.with_stubbed_jobs
    stub_jobs
    yield if block_given?
    unstub_jobs
  end

  def self.run_jboss?
    !ENV["RUN_JBOSS"].nil?
  end
end

if FakeTorquebox.run_jboss?
  require_relative 'setup_torquespec'
else
  require_relative 'setup_faketorquespec'
end