# require 'spec_helper'
# require 'torquespec'
# require 'open-uri'
# require 'torquebox-core'

# require 'jruby'
# JRuby.objectspace = true

# describe "out of the container" do

#   # deploy <<-END.gsub(/^ {4}/,'')
#   #   application:
#   #     root: #{File.dirname(__FILE__)}/../apps/simple
#   # END

#   deploy BACKBEAT_APP

#   it "should still greet the world" do
#     #response = open("http://localhost:8080") {|f| f.read}
#     #response.strip.should == "Hello World!"
#     # ap "********************"
#     # ap TorqueBox::Messaging::Queue.list
#     # ap TorqueBox::MSC.deployment_unit
#     # ap TorqueBox::MSC.deployment_unit
#     queue = TorqueBox::Messaging::Queue.start('test')
#     # queue = TorqueBox::Messaging::Queue.start('/queues/my_queue')
#     queue.publish('bar')
#     binding.pry
#   end

#   def blocks
#     @blocks ||= []
#   end

#   before(:each) do
#     blocks.push :anything
#   end

#   after(:each) do
#     blocks.pop
#     blocks.should be_empty
#   end

#   remote_describe "in container of the same deployed app" do
#     include TorqueBox::Injectors

#     before(:each) do
#       blocks.push :anything
#     end

#     after(:each) do
#       blocks.pop
#       blocks.size.should == 1
#     end

#     it "remote? should work" do
#       TorqueSpec.remote{true}.should be_true
#       TorqueSpec.local{true}.should be_false
#     end

#     it "injection should work" do
#       __inject__( 'service-registry' ).should_not be_nil
#     end

#     it "should work" do
#       require 'torquebox/messaging/queue'
#       # TorqueBox::Messaging::Queue.list
#       queue = TorqueBox::Messaging::Queue.start('/queues/foo')
#       queue.publish('bar')
#       queue.receive.should == 'bar'
#       queue.stop
#     end

#   end

# end
require 'torquespec'
require 'open-uri'
require 'torquebox-messaging'
require 'spec_helper'


describe "simple backgrounding test" do

  deploy <<-DD_END.gsub(/^ {4}/,'')
    application:
      root: #{WorkflowServer::Config.root}/spec
  DD_END
  TorqueSpec.remote {
   ENV['RACK_ENV'] = "test"
 }

  it "should respond by spawning a background task" do
    #response = open("http://localhost:8080") {|f| f.read}
    #response.strip.should == "success"
    # ap "before inserting"
    # queue = TorqueBox::Messaging::Queue.new('/queues/accounting_backbeat_internalss')
    # start = Time.now.to_i
    # output = queue.publish('release')
    # p "Time taken #{Time.now.to_i - start}"
    FactoryGirl.create(:decision)
    queue = TorqueBox::Messaging::Queue.new('/queues/test')
    ap queue.receive(:timeout => 5000)
    ap "after inserting"
    binding.pry
    #TorqueBox::Messaging::Queue.new('/queue/abc').receive(:timeout => 5000).should == 'finished'
  end

end