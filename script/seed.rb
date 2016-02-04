3.times do |i|
  user = Backbeat::User.create!({
    name: "User #{i + 1}",
    activity_endpoint: "http://localhost:5000/#{i + 1}/activity",
    notification_endpoint: "http://localhost:5000/#{i + 1}/notification"
  })
  puts "Created user #{user.id}"
  workflow = Backbeat::Server.create_workflow({
    name: "Workflow #{i + 1}",
    subject: "Subject #{i + 1}",
    decider: "Decider #{i + 1}"
  }, user)
  puts "Created workflow #{workflow.id}"
  signal_params = {
    name: "Signal #{i + 1}",
    client_data: {
      params: [1, 2, 3],
      method: 'testing'
    }
  }
  node = Backbeat::Server.signal(workflow, signal_params)
  puts "Created node #{node.id}"
end
