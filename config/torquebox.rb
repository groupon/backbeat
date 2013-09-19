require File.join(File.dirname(__FILE__), "..", 'app')

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
    min 32
    max 32
  end

  pool :job do
    type :bounded
    min 1
    max 2
  end

  web do
    context '/'
  end

  service WorkflowServer::Services::SidekiqService do
    name 'backbeat_sidekiq_worker'
    config do
      queues ['accounting_backbeat_server']
      concurrency 32
    end
  end

  job WorkflowServer::Reports::DailyReport do
    cron '0 0 12 1/1 * ? *'
  end
end