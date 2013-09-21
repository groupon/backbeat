require File.join(File.dirname(__FILE__), '..', 'lib', 'workflow_server', 'config')

TorqueBox.configure do
  ruby do
    version '1.9'
    compile_mode 'jit'
  end

  environment do
    RACK_ENV WorkflowServer::Config.environment
  end

  web do
    context '/'
  end

  pool :web do
    type :shared
    min 30
    max 50
  end

  pool :services do
    type :bounded
    min 30
    max 30
  end

  service Services::SidekiqService do
    name 'backbeat_sidekiq_worker'
    config do
      queues ['accounting_backbeat_server']
      concurrency 1
    end
  end

  job Reports::DailyReport do
    # Every day at midnight
    cron '0 0 12 1/1 * ? *'
  end
end