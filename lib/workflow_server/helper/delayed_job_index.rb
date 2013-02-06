module Delayed
  module Backend
    module Mongoid
      class Job
        # We only reopen this class so that we can add an index
        # on handler since we query over it frequently.
        index({ handler: 1})
      end
    end
  end
end
