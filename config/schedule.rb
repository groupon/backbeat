set :output, "/data/accounting_service/shared/log/cron_log.log"
env 'PATH', '/usr/local/bin:/usr/bin:/usr/sbin:/sbin:/bin'

every 1.day, :at => '12:00' do
  runner 'puts "Running Daily Report at #{Time.now}"; Reports::DailyReport.perform'
end
