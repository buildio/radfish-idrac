# frozen_string_literal: true

require "spec_helper"

# Queue hygiene and the 409/LC068 recovery. The point of the recovery is that an application never
# has to know the iDRAC has a job queue: the adapter frees slots by deleting FINISHED jobs only,
# and retries the command once.
#
# The iDRAC client is a plain double here, not an instance_double: clear_completed_jobs and
# pending_config_jobs land in the idrac gem in the sibling PR (buildio/idrac), so a released idrac
# does not carry them yet. Switch this to instance_double once the gemspec requires that release.
RSpec.describe Radfish::IdracAdapter, "iDRAC job queue" do
  let(:adapter) { described_class.new(host: "h", username: "u", password: "p", port: 443, verify_ssl: false) }
  let(:idrac_client) { double("IDRAC::Client") }

  # The one 409 we have actually captured: us-east-1z n003, iDRAC9, buildio/build#1974 -- the
  # incident this whole change comes from. Dell's generic 409 body. It names no job, no queue and no
  # message id, which is exactly why the recovery is keyed on the status and not on the wording.
  let(:n003_409) { IDRAC::Error.new("Failed with status 409: A general error has occurred") }
  let(:lc068) { IDRAC::Error.new("Failed with status 409: a configuration job is already scheduled (IDRAC.2.9.LC068)") }
  let(:queue_full_result) { { status: :failed, error: "Failed importing SCP: the maximum number of jobs is reached" } }

  before { allow(IDRAC::Client).to receive(:new).and_return(idrac_client) }

  describe "#clear_completed_jobs" do
    it "delegates to the iDRAC client and returns the ids removed" do
      expect(idrac_client).to receive(:clear_completed_jobs).and_return(%w[JID_1 JID_2])
      expect(adapter.clear_completed_jobs).to eq(%w[JID_1 JID_2])
    end
  end

  describe "#pending_config_jobs" do
    it "delegates to the iDRAC client" do
      expect(idrac_client).to receive(:pending_config_jobs).and_return([{ "Id" => "JID_1", "JobState" => "Running" }])
      expect(adapter.pending_config_jobs.first["JobState"]).to eq("Running")
    end
  end

  describe "#free_job_queue_slots!" do
    it "waits out a Running job by polling it, then deletes only the finished jobs" do
      allow(idrac_client).to receive(:pending_config_jobs)
        .and_return([{ "Id" => "JID_RUN", "JobState" => "Running" }, { "Id" => "JID_SCHED", "JobState" => "Scheduled" }])
      expect(idrac_client).to receive(:wait_config_job).with("JID_RUN", timeout: 900).and_return("Completed")
      expect(idrac_client).not_to receive(:wait_config_job).with("JID_SCHED", anything)
      expect(idrac_client).to receive(:clear_completed_jobs).and_return(["JID_RUN"])

      expect(adapter.free_job_queue_slots!).to eq(["JID_RUN"])
    end

    it "never cancels anything: a Scheduled job is neither waited on nor deleted" do
      allow(idrac_client).to receive(:pending_config_jobs).and_return([{ "Id" => "JID_SCHED", "JobState" => "Scheduled" }])
      expect(idrac_client).not_to receive(:wait_config_job)
      expect(idrac_client).not_to receive(:drain_pending_config_jobs!)
      expect(idrac_client).not_to receive(:clear_jobs!)
      expect(idrac_client).to receive(:clear_completed_jobs).and_return([])

      expect(adapter.free_job_queue_slots!).to eq([])
    end

    it "skips the wait entirely when job_queue_wait is 0" do
      adapter.job_queue_wait = 0
      expect(idrac_client).not_to receive(:wait_config_job)
      expect(idrac_client).to receive(:clear_completed_jobs).and_return([])

      expect(adapter.free_job_queue_slots!).to eq([])
    end
  end

  describe "the 409 / LC068 recovery" do
    before { allow(idrac_client).to receive(:pending_config_jobs).and_return([]) }

    it "fires on the real n003 409, which explains nothing at all" do
      expect(idrac_client).to receive(:set_system_configuration_profile).and_raise(n003_409).ordered
      expect(idrac_client).to receive(:clear_completed_jobs).and_return(["JID_DONE"]).ordered
      expect(idrac_client).to receive(:set_system_configuration_profile).and_return({ status: :success }).ordered

      expect(adapter.set_system_configuration_profile({})[:status]).to eq(:success)
    end

    it "clears finished jobs and retries the command once, so the caller never sees the conflict" do
      expect(idrac_client).to receive(:set_system_configuration_profile).and_raise(lc068).ordered
      expect(idrac_client).to receive(:clear_completed_jobs).and_return(["JID_DONE"]).ordered
      expect(idrac_client).to receive(:set_system_configuration_profile).and_return({ status: :success }).ordered

      expect(adapter.set_system_configuration_profile({})[:status]).to eq(:success)
    end

    it "recovers from an SCP import that reports the conflict in its result instead of raising" do
      expect(idrac_client).to receive(:set_system_configuration_profile).and_return(queue_full_result).ordered
      expect(idrac_client).to receive(:clear_completed_jobs).and_return(["JID_DONE"]).ordered
      expect(idrac_client).to receive(:set_system_configuration_profile).and_return({ status: :success }).ordered

      expect(adapter.set_system_configuration_profile({})[:status]).to eq(:success)
    end

    it "retries once only, and surfaces the original error when the queue is still blocked" do
      expect(idrac_client).to receive(:set_system_configuration_profile).twice.and_raise(lc068)
      expect(idrac_client).to receive(:clear_completed_jobs).once.and_return(["JID_DONE"])

      expect { adapter.set_system_configuration_profile({}) }.to raise_error(IDRAC::Error, /LC068/)
    end

    it "does not retry when there is nothing finished to clear, and cancels nothing" do
      expect(idrac_client).to receive(:set_system_configuration_profile).once.and_raise(lc068)
      expect(idrac_client).to receive(:clear_completed_jobs).and_return([])
      expect(idrac_client).not_to receive(:drain_pending_config_jobs!)
      expect(idrac_client).not_to receive(:clear_jobs!)

      expect { adapter.set_system_configuration_profile({}) }.to raise_error(IDRAC::Error, /LC068/)
    end

    it "leaves an error that is not a 409 alone" do
      not_a_conflict = IDRAC::Error.new("Failed with status 500: the iDRAC is resetting")
      expect(idrac_client).to receive(:set_system_configuration_profile).once.and_raise(not_a_conflict)
      expect(idrac_client).not_to receive(:clear_completed_jobs)

      expect { adapter.set_system_configuration_profile({}) }.to raise_error(/iDRAC is resetting/)
    end

    it "does not reach commands outside the seam: a power 409 means 'already in that state'" do
      already_on = IDRAC::Error.new("Failed with status 409: the server is already powered on")
      expect(idrac_client).to receive(:power_on).once.and_raise(already_on)
      expect(idrac_client).not_to receive(:clear_completed_jobs)

      expect { adapter.power_on }.to raise_error(/already powered on/)
    end

    it "surfaces a genuinely different second failure as itself" do
      other = IDRAC::Error.new("Failed with status 500: the iDRAC is resetting")
      expect(idrac_client).to receive(:set_system_configuration_profile).and_raise(lc068).ordered
      expect(idrac_client).to receive(:clear_completed_jobs).and_return(["JID_DONE"]).ordered
      expect(idrac_client).to receive(:set_system_configuration_profile).and_raise(other).ordered

      expect { adapter.set_system_configuration_profile({}) }.to raise_error(/iDRAC is resetting/)
    end

    it "covers the other commands that schedule a config job" do
      { set_one_time_cd_boot: [], disable_boot_entries: [], ensure_uefi_boot: nil,
        set_boot_order_hd_first: nil }.each do |command, _|
        expect(idrac_client).to receive(command).and_raise(lc068).ordered
        expect(idrac_client).to receive(:clear_completed_jobs).and_return(["JID_DONE"]).ordered
        expect(idrac_client).to receive(command).and_return(true).ordered

        expect(adapter.public_send(command)).to eq(true)
      end
    end

    it "passes a successful command straight through, untouched" do
      expect(idrac_client).to receive(:set_system_configuration_profile).once.and_return({ status: :success })
      expect(idrac_client).not_to receive(:clear_completed_jobs)

      expect(adapter.set_system_configuration_profile({})[:status]).to eq(:success)
    end
  end
end
