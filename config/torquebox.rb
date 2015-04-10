TorqueBox.configure do
  ruby do
    version '1.9'
    compile_mode 'jit'
  end

  web do
    context '/'
  end

  pool :web do
    type :shared
    lazy false
  end

  pool :services do
    type :bounded
    min 2
    max 2
  end

  service Services::SidekiqService do
    name "backbeat_sidekiq_worker_pool"
    config do
      queues ['accounting_backbeat_server', 'accounting_backbeat_server_v2']
      concurrency 200
      index 1
      # We have to use options here because timeout is an implemented method in this scope and raises an error rather then setting the config value correctly
      options timeout: 10
    end
  end

  service Services::SidekiqService do
    name "backbeat_migration_pool"
    config do
      queues ['accounting_backbeat_signal_delegation', 'accounting_backbeat_migrator']
      concurrency 20
      index 2
      # We have to use options here because timeout is an implemented method in this scope and raises an error rather then setting the config value correctly
      options timeout: 10
    end
  end

  if `hostname` =~ /accounting-utility2/
    job Reports::LogCounts do
      # Every 5 minutes
      cron '0 */5 * * * ?'
    end
  end

  if ENV['RACK_ENV'] == 'production' &&
    `hostname` =~ /accounting-utility2/

    job Reports::DailyReport do
      # Every day at midnight
      cron '0 0 12 1/1 * ? *'
    end
    job Reports::BadEvents do
      # Every day at 11 am (pick a time when we are not busy)
      cron '0 0 11 * * ?'
    end
  end
end
