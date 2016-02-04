require "spec_helper"

describe Backbeat::Web::CurrentUserHelper do
  FakeApi = Struct.new(:env) do
    include Backbeat::Web::CurrentUserHelper
  end

  context "#current_user" do
    let(:api) { FakeApi.new({ "HTTP_CLIENT_ID" => user.id }) }
    let(:user) { FactoryGirl.build(:user) }

    context "user exists" do
      before do
        allow(Backbeat::User).to receive(:find).and_return(user)
      end

      it "returns user" do
        expect(api.current_user).to eq(user)
      end
    end

    context "user does not exist" do
      before do
        allow(Backbeat::User).to receive(:find).and_raise(ActiveRecord::RecordNotFound.new)
      end

      it "returns false" do
        expect(api.current_user).to eq(false)
      end
    end

    context "connection error occurs" do
      before do
        allow(Backbeat::User).to receive(:find).and_raise(StandardError.new("could not connect to db!"))
      end

      it "returns false" do
        expect(api.current_user).to eq(false)
      end

      it "logs error" do
        expect(Backbeat::Logger).to receive(:info).with(
          message: "Error occurred while finding user",
          error: "could not connect to db!",
          backtrace: anything
        ).and_call_original

        api.current_user
      end
    end
  end
end
