role :utility, "fed2-tat.snc1", :primary => true
role :delayed_job, "fed2-tat.snc1"
set :branch, ENV["branch"] if ENV["branch"]
set :branch, ENV["BRANCH"] if ENV["BRANCH"]
