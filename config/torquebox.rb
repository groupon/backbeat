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

  2.times do |i|
    service Services::SidekiqService do
      name "backbeat_sidekiq_worker_pool_#{i}"
      config do
        queues ['accounting_backbeat_server']
        concurrency 25
        index i
        # We have to use options here because timeout is an implemented method in this scope and raises an error rather then setting the config value correctly
        options timeout: 600
      end
    end
  end

  job Reports::DailyReport do
    # Every day at midnight
    cron '0 0 12 1/1 * ? *'
  end
end
