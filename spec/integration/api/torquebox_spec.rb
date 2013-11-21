# require 'spec_helper'
# 
# describe "outside the container" do
#   include Rack::Test::Methods
# 
#   deploy BACKBEAT_APP
#   def app
#     FullRackApp
#   end
#   let(:user) { FactoryGirl.create(:user) }
# 
#   before do
#     header 'CLIENT_ID', RSPEC_CONSTANT_USER_CLIENT_ID
#     p "creating workflow"
#     @wf = FactoryGirl.create(:workflow, user: user)
#     p "workflow ready, creating decision"
#   end
#   remote_describe "running a remote spec by keeping an on count" do
#     before do
#       ap TorqueBox::Messaging::Queue.list.map {|t| "#{t.name} #{t.count_messages}" }
#       ap TorqueBox::Messaging::Queue.list.map {|t| t.remove_messages }
#     end
#     it "drops a signal" do
#       ap "before post call"
#       post "/workflows/#{@wf.id}/signal/test", options: { client_data: {data: '123'}, client_metadata: {metadata: '456'} }
#       ap "after post call"
#       loop {
#               #ap "inside loop"
#               #ap TorqueBox::Messaging::Queue.list
#               array = TorqueBox::Messaging::Queue.list.map do |destination|
#                 ap "looking at #{destination.name} #{destination.count_messages}"
#                 destination.count_messages
#               end
#               break if array.uniq == [0]
#               #ap "loop end #{array}"
#               sleep 5
#             }
#     end
#   end
# 
#   remote_describe "convert publish to publish and receive (the bug)" do
#     before do
#       ap TorqueBox::Messaging::Queue.list.map {|t| "#{t.name} #{t.count_messages}" }
#       ap TorqueBox::Messaging::Queue.list.map {|t| t.remove_messages }
#     end
#     require 'fake_torquebox'
#     it "drops a signal" do
#       ap "before post call"
#       post "/workflows/#{@wf.id}/signal/test", options: { client_data: {data: '123'}, client_metadata: {metadata: '456'} }
#       ap "after post call"
#       sleep 20
#     end
#   end
# end