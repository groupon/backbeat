require "spec_helper"

describe V2::NodeDetail, v2: true do

  context "retries remaining" do
    it "is invalid if less than 0" do
      detail = described_class.create(retries_remaining: -1)
      expect(detail.errors["retries_remaining"]).to_not be_empty
    end
  end
end
