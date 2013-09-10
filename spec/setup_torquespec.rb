require 'torquespec'

TorqueSpec.configure do |config|
  config.jboss_home = "#{ENV['HOME']}/.immutant/current/jboss"
  config.jvm_args = "-Xms2048m -Xmx2048m -XX:MaxPermSize=512m -XX:+UseConcMarkSweepGC -XX:+UseParNewGC -XX:+CMSClassUnloadingEnabled -Djruby.home=#{config.jruby_home}"
end

module TorqueBox
  module Messaging
    class Queue < Destination
      # publish_and_receive ensures that jobs run synchronously
      alias_method :publish, :publish_and_receive
    end
  end
end