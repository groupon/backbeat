module Backbeat
  class InvalidStatusChange < StandardError; end
  class InvalidServerStatusChange < InvalidStatusChange; end
  class InvalidClientStatusChange < InvalidStatusChange
    attr_reader :data

    def initialize(message, data = {})
      @data = data
      super(message)
    end
  end

  class WorkflowComplete < StandardError; end
  class StaleStatusChange < StandardError; end
  class DeserializeError < StandardError; end

  class InvalidParameters < StandardError
    def initialize(raw_message)
      @raw_message = raw_message
      super
    end

    def message
      @raw_message
    end
  end

  class HttpError < StandardError
    attr_reader :response
    def initialize(message, response)
      @response = response
      super(message)
    end
  end
end
