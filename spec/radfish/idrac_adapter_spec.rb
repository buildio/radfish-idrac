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

    describe "#virtual_media" do
      it "delegates to the iDRAC client" do
        media_data = []
        expect(idrac_client).to receive(:virtual_media).and_return(media_data)
        expect(adapter.virtual_media).to eq(media_data)
      end
    end
  end
end