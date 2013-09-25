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

  2.times do |index|
    service Services::SidekiqService do
      name "backbeat_sidekiq_worker_pool_#{index}"
      config do
        queues ['accounting_backbeat_server']
        concurrency 25
        timeout 600
        index index
      end
    end
  end

  job Reports::DailyReport do
    # Every day at midnight
    cron '0 0 12 1/1 * ? *'
  end
end
