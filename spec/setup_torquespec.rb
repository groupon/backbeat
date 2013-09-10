require 'torquespec'

module TorqueBox
  module Messaging
    class Queue < Destination
      # publish_and_receive ensures that jobs run synchronously
      alias_method :publish, :publish_and_receive
    end
  end
end