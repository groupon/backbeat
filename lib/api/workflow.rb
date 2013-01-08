require 'grape'
require 'workflow_server'

module Api
  class Workflow < Grape::API
    format :json

    resource 'workflows' do
      post "/" do
        wf = WorkflowServer::Manager.find_or_create_workflow(params[:workflow_type], params[:subject_type], params[:subject_id], params[:decider])
        ap wf.attributes
        [201, {}, wf]
      end
    end
    
    get "/events/:id" do
      
    end
  end
end

# class Posts < Grape::API
#   
#   version 'v1', :using => :path
#   format :json
#   
#   resource 'posts' do
#     get "/" do
#       f = Fiber.current
#       puts "Before #{Time.now.to_i}"
#       EventMachine.add_timer 1, proc { f.resume }
#       Fiber.yield
# 
#       puts "After #{Time.now.to_i}"
#       #puts f
#       puts "in get #{self}"
#       [200, {}, "Surprise!"]
#       
#       #Post.all
#     end
#     
#     get "/:id" do
#       puts "in get"
#       #ap params
#       #ap env
#       [200, {}, {}]
#       #Post.find(params['id'])
#     end
#     
#     post "/create" do
#       #Post.create(params['post'])
#     end
#   end
#   
# end