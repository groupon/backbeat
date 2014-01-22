module Api
  class DelayedJobStats
    def initialize(app)
      @app = app
    end

    ENDPOINT = '/delayed_job_stats'
    def call(env)
      if env['PATH_INFO'] == ENDPOINT
        priority = Delayed::Worker.default_priority
        run_at_threshold = Time.now

        req = Rack::Request.new(env)
        if req.params["priority"]
          priority = req.params["priority"].to_i
        end

        if req.params["delta"]
          run_at_threshold += req.params["delta"].to_i
        end

        data = { cutoff_time:   run_at_threshold,
                 job_priority:  priority,
                 jobs_past_due: Delayed::Job.where(locked_by: nil, priority: priority, :run_at.lte => run_at_threshold, failed_at: nil).count }

        return [ 200, {"Content-Type" => "application/json"}, [ data.to_json ] ]
      end

      @app.call(env)
    end
  end
end
