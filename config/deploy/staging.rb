role :utility, "fed1-tat.snc1", :primary => true
role :delayed_job, "fed1-tat.snc1"
set :branch, ENV["branch"] if ENV["branch"]
set :branch, ENV["BRANCH"] if ENV["BRANCH"]
