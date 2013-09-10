require_relative 'mock_session'

module FakeTorquebox
  VERSION = "0.0.1"

  def self.for
    yield if block_given?
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