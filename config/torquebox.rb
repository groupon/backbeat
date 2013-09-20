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
    min 16
    max 32
  end

  # pool :services do
  #   type :shared
  #   min 32
  #   max 32
  # end

  service Services::SidekiqService do
    name 'backbeat_sidekiq_worker'
    config do
      queues ['accounting_backbeat_server']
      concurrency 32
    end
  end

  job Reports::DailyReport do
    # Every day at midnight
    cron '0 0 12 1/1 * ? *'
  end
end