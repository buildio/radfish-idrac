# frozen_string_literal: true

require "spec_helper"

RSpec.describe Radfish::IdracAdapter do
  let(:host) { "192.168.1.100" }
  let(:username) { "admin" }
  let(:password) { "password" }
  let(:options) { { port: 443, verify_ssl: false } }
  
  let(:adapter) do
    described_class.new(
      host: host,
      username: username,
      password: password,
      **options
    )
  end

  describe "#initialize" do
    it "creates an adapter instance" do
      expect(adapter).to be_a(described_class)
    end

    it "stores the iDRAC client" do
      expect(adapter.idrac_client).to be_a(IDRAC::Client)
    end
  end

  describe "#vendor" do
    it "returns 'dell'" do
      expect(adapter.vendor).to eq("dell")
    end
  end

  describe "delegation to iDRAC client" do
    let(:idrac_client) { instance_double(IDRAC::Client) }

    before do
      allow(IDRAC::Client).to receive(:new).and_return(idrac_client)
    end

    describe "#login" do
      it "delegates to the iDRAC client" do
        expect(idrac_client).to receive(:login)
        adapter.login
      end
    end

    describe "#logout" do
      it "delegates to the iDRAC client" do
        expect(idrac_client).to receive(:logout)
        adapter.logout
      end
    end

    describe "#power_status" do
      it "delegates to the iDRAC client" do
        expect(idrac_client).to receive(:get_power_state).and_return("On")
        expect(adapter.power_status).to eq("On")
      end
    end

    describe "#system_info" do
      it "transforms iDRAC client data to radfish format" do
        system_data = { 
          "service_tag" => "ABC123",
          "model" => "PowerEdge R640",
          "firmware_version" => "4.40.00.00",
          "idrac_version" => "4.40.00.00",
          "is_dell" => true
        }
        expect(idrac_client).to receive(:system_info).and_return(system_data)
        
        result = adapter.system_info
        expect(result[:service_tag]).to eq("ABC123")
        expect(result[:make]).to eq("Dell")
        expect(result[:manufacturer]).to eq("Dell")
        expect(result[:model]).to eq("R640")  # PowerEdge prefix stripped
        expect(result[:serial]).to eq("ABC123")  # Dell uses service tag as serial
      end
    end
    
    describe "#service_tag" do
      it "returns the service tag from iDRAC client" do
        system_data = { "service_tag" => "ABC123" }
        expect(idrac_client).to receive(:system_info).and_return(system_data)
        expect(adapter.service_tag).to eq("ABC123")
      end
    end
    
    describe "#make" do
      it "returns Dell" do
        expect(adapter.make).to eq("Dell")
      end
    end
    
    describe "#model" do
      it "returns the model with PowerEdge prefix stripped" do
        system_data = { "model" => "PowerEdge R640" }
        expect(idrac_client).to receive(:system_info).and_return(system_data)
        expect(adapter.model).to eq("R640")
      end
    end
    
    describe "#serial" do
      it "returns the service tag as serial" do
        system_data = { "service_tag" => "ABC123" }
        expect(idrac_client).to receive(:system_info).and_return(system_data)
        expect(adapter.serial).to eq("ABC123")
      end
    end

    # A restart is not a power off. Routed through the iDRAC gem's power_off, a ForceRestart waits
    # for PowerState "Off" it will never reach, and the failed wait escalates to ForceOff — which
    # is how an iDRAC8 node was left powered down for 22 minutes.
    describe "#reboot" do
      it "sends a restart, never a power off" do
        expect(idrac_client).not_to receive(:power_off)
        expect(idrac_client).to receive(:reboot).with(kind: "ForceRestart", wait: false).and_return(true)
        adapter.reboot(type: "ForceRestart", wait: false)
      end

      it "passes the caller's wait through instead of dropping it" do
        expect(idrac_client).to receive(:reboot).with(kind: "ForceRestart", wait: true).and_return(false)
        adapter.reboot(type: "ForceRestart", wait: true)
      end

      # iDRAC8 has no GracefulRestart among its allowable reset types.
      it "falls back to ForceRestart when GracefulRestart is refused, and still does not power off" do
        expect(idrac_client).not_to receive(:power_off)
        expect(idrac_client).to receive(:reboot).with(kind: "GracefulRestart", wait: false)
                                                .and_raise(IDRAC::Error, "not allowed")
        expect(idrac_client).to receive(:reboot).with(kind: "ForceRestart", wait: false).and_return(true)
        adapter.reboot(type: "GracefulRestart", wait: false)
      end

      it "re-raises a failure of a non-graceful restart rather than powering the host off" do
        expect(idrac_client).not_to receive(:power_off)
        expect(idrac_client).to receive(:reboot).with(kind: "ForceRestart", wait: false)
                                                .and_raise(IDRAC::Error, "boom")
        expect { adapter.reboot(type: "ForceRestart", wait: false) }.to raise_error(IDRAC::Error, "boom")
      end
    end

    describe "#power_off" do
      it "refuses a restart type instead of powering the host down" do
        expect(idrac_client).not_to receive(:power_off)
        expect { adapter.power_off(type: "ForceRestart") }.to raise_error(ArgumentError, /use #reboot/)
      end

      it "passes a shutdown type and the caller's wait to the iDRAC client" do
        expect(idrac_client).to receive(:power_off).with(kind: "GracefulShutdown", wait: false).and_return(true)
        adapter.power_off(type: "GracefulShutdown", wait: false)
      end
    end

    describe "#virtual_media" do
      it "delegates to the iDRAC client" do
        media_data = []
        expect(idrac_client).to receive(:virtual_media).and_return(media_data)
        expect(adapter.virtual_media).to eq(media_data)
      end
    end

    describe "#insert_virtual_media" do
      it "delegates to the iDRAC client" do
        expect(idrac_client).to receive(:insert_virtual_media).with("http://example.com/test.iso", device: "CD")
        adapter.insert_virtual_media("http://example.com/test.iso")
      end

      it "rescues IDRAC::Error (not Idrac::Error) and translates to Radfish error" do
        expect(idrac_client).to receive(:insert_virtual_media).and_raise(IDRAC::Error, "connection refused")
        expect { adapter.insert_virtual_media("http://example.com/test.iso") }
          .to raise_error(Radfish::VirtualMediaConnectionError, /BMC cannot reach/)
      end

      it "translates timeout errors" do
        expect(idrac_client).to receive(:insert_virtual_media).and_raise(IDRAC::Error, "operation timeout")
        expect { adapter.insert_virtual_media("http://example.com/test.iso") }
          .to raise_error(Radfish::TaskTimeoutError, /timed out/)
      end

      it "translates generic iDRAC errors to VirtualMediaError" do
        expect(idrac_client).to receive(:insert_virtual_media).and_raise(IDRAC::Error, "something unexpected")
        expect { adapter.insert_virtual_media("http://example.com/test.iso") }
          .to raise_error(Radfish::VirtualMediaError, "something unexpected")
      end
    end

    describe "#eject_virtual_media" do
      it "delegates to the iDRAC client" do
        expect(idrac_client).to receive(:eject_virtual_media).with(device: "CD")
        adapter.eject_virtual_media
      end

      it "rescues IDRAC::Error (not Idrac::Error) and translates to Radfish error" do
        expect(idrac_client).to receive(:eject_virtual_media).and_raise(IDRAC::Error, "device not found")
        expect { adapter.eject_virtual_media }
          .to raise_error(Radfish::VirtualMediaNotFoundError, /not found/)
      end

      it "translates generic iDRAC errors to VirtualMediaError" do
        expect(idrac_client).to receive(:eject_virtual_media).and_raise(IDRAC::Error, "unexpected error")
        expect { adapter.eject_virtual_media }
          .to raise_error(Radfish::VirtualMediaError, /Failed to eject/)
      end
    end
  end
end