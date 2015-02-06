module SidekiqHelper
  # Acknowledges perform_in time and does not drain jobs that a drained job enqueues
  def soft_drain
    jobs = V2::Workers::AsyncWorker.jobs
    0.upto(jobs.count - 1) do |i|
      job = jobs[i]
      if !job["at"] || Time.now.to_f > job["at"]
        worker = V2::Workers::AsyncWorker.new
        worker.jid = job['jid']
        args = job['args']
        jobs[i] = nil
        worker.perform(*args)
      end
    end
  ensure
    jobs.compact!
  end
end
