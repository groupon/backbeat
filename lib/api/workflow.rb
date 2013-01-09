require 'grape'
require 'workflow_server'

module Api
  class Workflow < Grape::API
    format :json

    helpers do
      def current_user
        @current_user ||= env['WORKFLOW_CURRENT_USER']
      end
    end

    resource 'workflows' do
      params do
        requires :workflow_type, :type => String, :desc => 'Require a workflow type'
        requires :subject_type,  :type => String, :desc => 'Require a subject type'
        requires :subject_id,    :type => String, :desc => 'Require a subject id'
        requires :decider,       :type => String, :desc => 'Require a workflow decider'
      end
      post "/" do
        wf = WorkflowServer::Manager.find_or_create_workflow(params[:workflow_type], params[:subject_type], params[:subject_id], params[:decider], current_user)
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