TorqueBox.configure do
  ruby do
    version '1.9'
    compile_mode 'jit'
  end

  web do
    context '/'
  end

  pool :web do
    type :bounded
    min 10
    max 50
  end

  service Services::SidekiqService do
    name 'backbeat_sidekiq_worker'
    config do
      queues ['accounting_backbeat_server']
      concurrency 50
    end
  end

  job Reports::DailyReport do
    # Every day at midnight
    cron '0 0 12 1/1 * ? *'
  end
end
