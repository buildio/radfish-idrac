# frozen_string_literal: true

require "spec_helper"

RSpec.describe Radfish::IdracAdapter, "boot/power delegation moved out of the app" do
  let(:adapter) { described_class.new(host: "h", username: "u", password: "p", port: 443, verify_ssl: false) }
  let(:idrac_client) { instance_double(IDRAC::Client) }

  before { allow(IDRAC::Client).to receive(:new).and_return(idrac_client) }

  describe "#stale_uefi_boot_entries" do
    it "delegates to the iDRAC client" do
      expect(idrac_client).to receive(:stale_uefi_boot_entries).and_return([{ "Name" => "Unknown.Unknown.1-1" }])
      expect(adapter.stale_uefi_boot_entries.first["Name"]).to eq("Unknown.Unknown.1-1")
    end
  end

  describe "#disable_boot_entries" do
    it "delegates, passing through a match option" do
      expect(idrac_client).to receive(:disable_boot_entries).with(match: /Optical/).and_return(["Optical.iDRACVirtual.1-1"])
      expect(adapter.disable_boot_entries(match: /Optical/)).to eq(["Optical.iDRACVirtual.1-1"])
    end
  end

  describe "#power_state" do
    it "returns the live BMC power state (replacing the app reach-through)" do
      expect(idrac_client).to receive(:get_power_state).and_return("On")
      expect(adapter.power_state).to eq("On")
    end
  end

  describe "#boot_progress" do
    it "delegates to the iDRAC client" do
      expect(idrac_client).to receive(:boot_progress).and_return(:os_running)
      expect(adapter.boot_progress).to eq(:os_running)
    end
  end

  describe "#drain_pending_config_jobs!" do
    it "delegates to the iDRAC client" do
      expect(idrac_client).to receive(:drain_pending_config_jobs!).and_return(["JID_1"])
      expect(adapter.drain_pending_config_jobs!).to eq(["JID_1"])
    end
  end

  describe "#boot_progress_ceiling" do
    it "gives the EPYC R6525/R7525 a longer POST ceiling than the R630/R640" do
      allow(idrac_client).to receive(:system_info).and_return("model" => "PowerEdge R6525")
      expect(adapter.boot_progress_ceiling).to eq(1200)
    end

    it "returns the default for an unmapped model" do
      allow(idrac_client).to receive(:system_info).and_return("model" => "PowerEdge R750")
      expect(adapter.boot_progress_ceiling).to eq(described_class::DEFAULT_BOOT_PROGRESS_CEILING)
    end
  end
end
