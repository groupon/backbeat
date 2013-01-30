role :utility, "accounting-utility1-uat.snc1", :primary => true
role :delayed_job, "accounting-utility1-uat.snc1"
role :db, "accounting-mongodb1.snc1", :primary => true
role :db, "accounting-mongodb2.snc1"
role :db, "accounting-mongodb3.snc1"

set :branch, ENV["branch"] if ENV["branch"]
set :branch, ENV["BRANCH"] if ENV["BRANCH"]
