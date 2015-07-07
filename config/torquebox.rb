require File.expand_path('../environment',  __FILE__)
require File.expand_path('../sidekiq_service', __FILE__)
Bundler.require(:torquebox)

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
    name "backbeat_sidekiq"
    config do
      queues [Backbeat::Config.options['async_queue']]
      strict true
      concurrency 15
      index 2
      options timeout: 10
    end
  end
end
