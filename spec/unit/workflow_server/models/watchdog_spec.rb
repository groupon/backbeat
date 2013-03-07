require 'spec_helper'

describe WorkflowServer::Models::Watchdog do
  subject = WorkflowServer::Models::Watchdog

  before do
    @wf = FactoryGirl.create(:workflow)
    @a1 = FactoryGirl.create(:activity, workflow: @wf).reload
  end

  context 'ClassMethods' do

    context 'start' do
      it 'dismisses any existing Watchdogs with the same subject and name' do
        subject.should_receive(:dismiss).with(@a1, :timeout)

        subject.start(@a1)
      end
      it 'does NOT dismiss Watchdogs with the same name but a different subject' do
        subject.start(@wf)
        subject.start(@a1)

        subject.count.should eq 2
      end
      it 'does NOT dismiss Watchdogs with the same subject but a different name' do
        subject.start(@a1, :my_timeout)
        subject.start(@a1)

        subject.count.should eq 2
      end
      it 'defaults name to :timeout' do
        wd = subject.start(@a1)

        wd.name.should eq :timeout
      end
      it 'defaults starves_in to 30 minutes' do
        wd = subject.start(@a1)

        wd.starves_in.should eq 30.minutes
      end
      it 'has its timer' do
        wd = subject.start(@a1)

        wd.timer.should eq Delayed::Job.last
      end
      it 'creates a new Watchdog' do
        subject.start(@a1)

        subject.count.should eq 1
      end
    end

    [:feed, :kick, :pet, :wake].each do |method|
      context "#{method}" do
        it 'searches for the Watchdog to feed' do
          wd = subject.start(@a1, :my_timeout)
          subject.should_receive(:where).with(subject: @a1, name: :my_timeout).and_return([wd])

          subject.send(method, @a1, :my_timeout)
        end
        it 'feeds the existing Watchdog if it exists' do
          subject.start(@a1)
          subject.any_instance.should_receive(:feed)

          subject.send(method, @a1)
        end
        it 'starts a new Watchdog if it does NOT exist' do
          subject.should_receive(:start).with(@a1, :my_timeout)

          subject.send(method, @a1, :my_timeout)
        end
        it 'defaults name to :timeout' do
          subject.should_receive(:start).with(@a1, :timeout)

          subject.send(method, @a1)
        end
      end
    end

    [:dismiss, :stop, :kill].each do |method|
      context "#{method}" do
        it 'destroys the Watchdog that matches the passed args' do
          subject.start(@a1)
          subject.send(method, @a1)

          subject.count.should eq 0
        end
      end
    end

    [:mass_dismiss, :mass_stop, :mass_kill].each do |method|
      context "#{method}" do
        it 'destroys all the Watchdogs on a subject' do
          subject.start(@a1)
          subject.start(@a1, :my_timeout)
          subject.start(@a1, :please_not_broken_timeout)

          subject.count.should eq 3

          subject.send(method, @a1)

          subject.count.should eq 0
        end
      end
    end
  end

  context 'InstanceMethods' do

    [:feed, :kick, :pet, :wake].each do |method|
      context "#{method}" do
        it 'extends the Watchdogs timer by the starves_in time' do
          wd = subject.start(@a1, :my_timeout)
          Delayed::Job.any_instance.should_receive(:update_attributes!).with(run_at: (Time.now + 30.minutes))

          subject.send(method, @a1, :my_timeout)

          wd.reload.timer.should_not be_nil
        end
      end
    end

    [:dismiss, :stop, :kill].each do |method|
      context "#{method}" do
        it 'destroys the Watchdog' do
          wd = subject.start(@a1)
          wd.send(method)

          subject.count.should eq 0
        end
      end
    end
  end

  it 'is unique between subject and name' do
    subject.start(@a1, :my_timeout)
    subject.start(@a1, :my_timeout)
    subject.start(@a1, :my_timeout)

    subject.count.should eq 1
  end

  it 'destroys it\'s timer when it is destroyed' do
    Delayed::Job.count.should eq 0
    wd = subject.start(@a1, :my_timeout)
    Delayed::Job.count.should eq 1
    wd.destroy
    Delayed::Job.count.should eq 0
  end

  it 'requires a name and a subject' do
    expect{subject.create!(starves_in: 11.minutes)}.to raise_error
  end

  it 'has it\'s subject' do
    subject.start(@a1, :my_timeout).subject.should eq @a1
  end
end
