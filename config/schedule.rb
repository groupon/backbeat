set :output, "/var/groupon/backbeat/shared/log/cron.log"
env 'PATH', '/usr/local/bin:/usr/bin:/usr/sbin:/sbin:/bin'

every 1.day, :at => '12:00' do
  runner 'puts "Running Daily Report at #{Time.now}"; Reports::DailyReport.perform'
end
