require "spec_helper"

describe "Serializers", v2: true do
  describe V2::Client::ErrorSerializer do
    it "formats the hash for StandardErrors" do
      error = StandardError.new('some_error')
      expect(V2::Client::ErrorSerializer.call(error)).to eq({
        error_klass: error.class.to_s,
        message: error.message
      })
    end

    it "adds backtrace if it exists" do
      begin
        raise StandardError.new('some_error')
      rescue => error
        expect(V2::Client::ErrorSerializer.call(error)).to eq({
          error_klass: error.class.to_s,
          message: error.message,
          backtrace: error.backtrace
        })
      end
    end

    it "formats the hash for strings" do
      error = "blah"
      expect(V2::Client::ErrorSerializer.call(error)).to eq({
        error_klass: error.class.to_s,
        message: error
      })
    end

    it "doesn't format for other other class types" do
      error = 1
      expect(V2::Client::ErrorSerializer.call(error)).to eq(1)
    end
  end
end
