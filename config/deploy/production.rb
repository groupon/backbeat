role :utility,     'accounting-utility2.snc1', :primary => true
role :delayed_job, 'accounting-utility2.snc1'
role :resque_backbeat_server, 'accounting-utility2.snc1'
role :cronjobs,    'accounting-utility2.snc1'

set :branch, ENV['branch'] if ENV['branch']
set :branch, ENV['BRANCH'] if ENV['BRANCH']
