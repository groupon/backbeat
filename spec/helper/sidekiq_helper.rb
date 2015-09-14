module SidekiqHelper
  # Acknowledges perform_in time and does not drain jobs that a drained job enqueues
  def soft_drain
    jobs = Backbeat::Workers::AsyncWorker.jobs

    #only drain current jobs in the queue
    job_count = jobs.count

    job_count.times do |i|
      job = jobs[i]
      if !job["at"] || Time.now.to_f > job["at"]
        worker = Backbeat::Workers::AsyncWorker.new
        worker.jid = job['jid']
        args = job['args']
        jobs[i] = nil
        worker.perform(*args)
      end
    end
  ensure
    jobs.compact!
  end
  module_function :soft_drain

  def show_jobs_in_queue
    Backbeat::Workers::AsyncWorker.jobs.each{|job| ap job}
  end
end
