role :utility, "accounting-utility1-uat.snc1", :primary => true
set :branch, ENV["branch"] if ENV["branch"]
set :branch, ENV["BRANCH"] if ENV["BRANCH"]