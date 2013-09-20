require File.join(File.dirname(__FILE__), '..', 'app')

TorqueBox.configure do
  ruby do
    version '1.9'
    compile_mode 'jit'
  end

  environment do
    RACK_ENV WorkflowServer::Config.environment
  end

  pool :web do
    type :shared
    min 1
    max 1
  end

  pool :job do
    type :bounded
    min 1
    max 2
  end

  web do
    context '/'
  end

  service Services::SidekiqService do
    name 'backbeat_sidekiq_worker'
    config do
      queues ['accounting_backbeat_server']
      concurrency 1
    end
  end

  job WorkflowServer::Reports::DailyReport do
    # Every day at midnight
    cron '0 0 12 1/1 * ? *'
  end
end
