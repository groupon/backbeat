require "spec_helper"

describe Backbeat::Web::CurrentUserHelper do
  class DummyClass
    include Backbeat::Web::CurrentUserHelper
  end

  context "#current_user" do
    let(:user) { FactoryGirl.build(:user) }

    before do
      allow_any_instance_of(DummyClass).to receive(:env).and_return({"HTTP_CLIENT_ID" => user.id})
    end

    context "user exists" do
      before do
        allow(Backbeat::User).to receive(:find).and_return(user)
      end

      it "returns user" do
        expect(DummyClass.new.current_user).to eq(user)
      end
    end

    context "user does not exist" do
      before do
        allow(Backbeat::User).to receive(:find).and_raise(ActiveRecord::RecordNotFound.new)
      end

      it "returns false" do
        expect(DummyClass.new.current_user).to eq(false)
      end
    end

    context "connection error occurs" do
      before do
        allow(Backbeat::User).to receive(:find).and_raise(StandardError.new("could not connect to db!"))
      end

      it "returns false" do
        expect(DummyClass.new.current_user).to eq(false)
      end

      it "logs error" do
        expect(Backbeat::Logger).to receive(:info).with(
          message: "error occured while finding user",
          error: "could not connect to db!",
          backtrace: anything
        ).and_call_original

        DummyClass.new.current_user
      end
    end
  end
end
