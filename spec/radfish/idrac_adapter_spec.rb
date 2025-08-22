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
      expect(adapter.idrac_client).to be_a(Idrac::Client)
    end
  end

  describe "#vendor" do
    it "returns 'dell'" do
      expect(adapter.vendor).to eq("dell")
    end
  end

  describe "delegation to iDRAC client" do
    let(:idrac_client) { instance_double(Idrac::Client) }

    before do
      allow(Idrac::Client).to receive(:new).and_return(idrac_client)
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
        expect(idrac_client).to receive(:power_status).and_return("On")
        expect(adapter.power_status).to eq("On")
      end
    end

    describe "#system_info" do
      it "delegates to the iDRAC client" do
        system_data = { 
          "ServiceTag" => "ABC123",
          "Model" => "PowerEdge R640"
        }
        expect(idrac_client).to receive(:system_info).and_return(system_data)
        expect(adapter.system_info).to eq(system_data)
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