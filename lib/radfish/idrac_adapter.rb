# frozen_string_literal: true

require 'radfish'
require 'idrac'

module Radfish
  class IdracAdapter < Core::BaseClient
    include Core::Power
    include Core::System
    include Core::Storage
    include Core::VirtualMedia
    include Core::Boot
    include Core::Jobs
    include Core::Utility
    
    attr_reader :idrac_client
    
    def initialize(host:, username:, password:, **options)
      super
      
      # Create the underlying iDRAC client
      @idrac_client = IDRAC::Client.new(
        host: host,
        username: username,
        password: password,
        port: options[:port] || 443,
        use_ssl: options.fetch(:use_ssl, true),
        verify_ssl: options.fetch(:verify_ssl, false),
        direct_mode: options.fetch(:direct_mode, false),
        retry_count: options[:retry_count] || 3,
        retry_delay: options[:retry_delay] || 1,
        host_header: options[:host_header]
      )
    end
    
    def vendor
      'dell'
    end
    
    def verbosity=(value)
      super
      @idrac_client.verbosity = value if @idrac_client
    end
    
    # Session management
    
    def login
      @idrac_client.login
    end
    
    def logout
      @idrac_client.logout
    end
    
    def authenticated_request(method, path, **options)
      @idrac_client.authenticated_request(method, path, **options)
    end
    
    # Power management - delegate to iDRAC client
    
    def power_status
      @idrac_client.get_power_state
    end
    
    def power_on
      @idrac_client.power_on
    end
    
    def power_off(force: false)
      kind = force ? "ForceOff" : "GracefulShutdown"
      @idrac_client.power_off(kind: kind)
    end
    
    def power_restart(force: false)
      # iDRAC uses reboot method, which is ForceRestart by default
      if force
        @idrac_client.reboot
      else
        # Try graceful restart first
        @idrac_client.power_off(kind: "GracefulRestart") rescue @idrac_client.reboot
      end
    end
    
    def power_cycle
      # iDRAC doesn't have power_cycle, simulate with off then on
      power_off
      sleep 5
      power_on
    end
    
    def reset_type_allowed
      # iDRAC doesn't expose this directly, return common types
      ["On", "ForceOff", "GracefulShutdown", "GracefulRestart", "ForceRestart", "Nmi", "PushPowerButton"]
    end
    
    # System information
    
    def system_info
      @idrac_client.system_info
    end
    
    def cpus
      @idrac_client.cpus
    end
    
    def memory
      @idrac_client.memory
    end
    
    def nics
      @idrac_client.nics
    end
    
    def fans
      @idrac_client.fans
    end
    
    def temperatures
      @idrac_client.temperatures
    end
    
    def psus
      @idrac_client.psus
    end
    
    def power_consumption
      @idrac_client.power_consumption
    end
    
    # Storage
    
    def storage_controllers
      @idrac_client.storage_controllers
    end
    
    def drives
      @idrac_client.drives
    end
    
    def volumes
      @idrac_client.volumes
    end
    
    def storage_summary
      @idrac_client.storage_summary
    end
    
    # Virtual Media
    
    def virtual_media
      @idrac_client.virtual_media
    end
    
    def insert_virtual_media(iso_url, device: "CD")
      @idrac_client.insert_virtual_media(iso_url, device: device)
    end
    
    def eject_virtual_media(device: "CD")
      @idrac_client.eject_virtual_media(device: device)
    end
    
    def virtual_media_status
      @idrac_client.virtual_media
    end
    
    def mount_iso_and_boot(iso_url, device: "CD")
      insert_virtual_media(iso_url, device: device)
      boot_to_cd
    end
    
    def unmount_all_media
      media_list = virtual_media
      success = true
      
      media_list.each do |media|
        if media[:inserted]
          success &&= eject_virtual_media(device: media[:device])
        end
      end
      
      success
    end
    
    # Boot configuration
    
    def boot_options
      @idrac_client.boot_options
    end
    
    def set_boot_override(target, persistent: false)
      @idrac_client.set_boot_override(target, persistent: persistent)
    end
    
    def clear_boot_override
      @idrac_client.clear_boot_override
    end
    
    def set_boot_order(devices)
      @idrac_client.set_boot_order(devices)
    end
    
    def get_boot_devices
      @idrac_client.get_boot_devices
    end
    
    def boot_to_pxe
      @idrac_client.boot_to_pxe
    end
    
    def boot_to_disk
      @idrac_client.boot_to_disk
    end
    
    def boot_to_cd
      @idrac_client.boot_to_cd
    end
    
    def boot_to_usb
      @idrac_client.boot_to_usb
    end
    
    def boot_to_bios_setup
      @idrac_client.boot_to_bios_setup
    end
    
    # Jobs
    
    def jobs
      @idrac_client.jobs
    end
    
    def job_status(job_id)
      @idrac_client.job_status(job_id)
    end
    
    def wait_for_job(job_id, timeout: 600)
      @idrac_client.wait_for_job(job_id, timeout: timeout)
    end
    
    def cancel_job(job_id)
      @idrac_client.cancel_job(job_id)
    end
    
    def clear_completed_jobs
      @idrac_client.clear_jobs
    end
    
    def jobs_summary
      jobs
    end
    
    # Utility
    
    def sel_log
      @idrac_client.sel_log
    end
    
    def clear_sel_log
      @idrac_client.clear_sel_log
    end
    
    def sel_summary(limit: 10)
      @idrac_client.sel_summary(limit: limit)
    end
    
    def accounts
      @idrac_client.accounts
    end
    
    def create_account(username:, password:, role: "Administrator")
      @idrac_client.create_account(username: username, password: password, role: role)
    end
    
    def delete_account(username)
      @idrac_client.delete_account(username)
    end
    
    def update_account_password(username:, new_password:)
      @idrac_client.update_account_password(username: username, new_password: new_password)
    end
    
    def sessions
      @idrac_client.sessions
    end
    
    def service_info
      @idrac_client.service_info
    end
    
    def get_firmware_version
      @idrac_client.get_firmware_version
    end
    
    # Additional iDRAC-specific methods
    
    def screenshot
      @idrac_client.screenshot if @idrac_client.respond_to?(:screenshot)
    end
    
    def licenses
      @idrac_client.licenses if @idrac_client.respond_to?(:licenses)
    end
    
    def license_info
      @idrac_client.license_info if @idrac_client.respond_to?(:license_info)
    end
  end
  
  # Register the adapter
  Radfish.register_adapter('dell', IdracAdapter)
  Radfish.register_adapter('idrac', IdracAdapter)
end