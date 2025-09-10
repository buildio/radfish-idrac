# frozen_string_literal: true

require 'radfish'
require 'idrac'
require 'ostruct'

module Radfish
  class IdracAdapter < Core::BaseClient
    include Core::Power
    include Core::System
    include Core::Storage
    include Core::VirtualMedia
    include Core::Boot
    include Core::Jobs
    include Core::Utility
    include Core::Network
    
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
    
    def power_on(wait: true)
      result = @idrac_client.power_on
      
      if wait && result
        # Wait for power on to complete
        max_attempts = 30
        attempts = 0
        while attempts < max_attempts
          sleep 2
          begin
            status = power_state
            break if status == "On"
          rescue => e
            # BMC might be temporarily unavailable during power operations
            debug "Waiting for BMC to respond: #{e.message}", 1, :yellow
          end
          attempts += 1
        end
      end
      
      result
    end
    
    def power_off(type: "GracefulShutdown", wait: true)
      # Use the type parameter directly - it already uses Redfish standard values
      result = @idrac_client.power_off(kind: type)
      
      if wait && result
        # Wait for power off to complete
        max_attempts = 30
        attempts = 0
        while attempts < max_attempts
          sleep 2
          begin
            status = power_state
            break if status == "Off"
          rescue => e
            # BMC might be temporarily unavailable during power operations
            debug "Waiting for BMC to respond: #{e.message}", 1, :yellow
          end
          attempts += 1
        end
      end
      
      result
    end
    
    def reboot(type: "GracefulRestart", wait: true)
      # Use the type parameter - iDRAC's power_off can handle restart types
      begin
        result = @idrac_client.power_off(kind: type)
      rescue => e
        # If graceful restart fails, fall back to force restart
        if type == "GracefulRestart"
          debug "Graceful restart failed, using force restart", 1, :yellow
          result = @idrac_client.reboot  # This is ForceRestart
        else
          raise e
        end
      end
      
      if wait && result
        # Wait for system to go down then come back up
        max_attempts = 60
        attempts = 0
        went_down = false
        
        while attempts < max_attempts
          sleep 2
          begin
            status = power_state
            went_down = true if status == "Off" && !went_down
            break if went_down && status == "On"
          rescue => e
            # BMC might be temporarily unavailable during reboot
            debug "Waiting for BMC during reboot: #{e.message}", 1, :yellow
          end
          attempts += 1
        end
      end
      
      result
    end
    
    def power_cycle(wait: true)
      # Power cycle: turn off then on
      power_off(type: "ForceOff", wait: wait)
      sleep 5
      power_on(wait: wait)
    end
    
    def reset_type_allowed
      # iDRAC doesn't expose this directly, return common types
      ["On", "ForceOff", "GracefulShutdown", "GracefulRestart", "ForceRestart", "Nmi", "PushPowerButton"]
    end
    
    # System information
    
    def system_info
      # iDRAC gem returns string keys, convert to symbols for radfish
      info = @idrac_client.system_info
      
      # Dell servers always have "Dell Inc." as manufacturer
      # Normalize for consistency
      manufacturer = "Dell"
      
      model = info["model"]
      model = model&.gsub(/^PowerEdge\s+/i, '') if model  # Strip PowerEdge prefix
      
      {
        service_tag: info["service_tag"],
        manufacturer: manufacturer,
        make: manufacturer,
        model: model,
        serial: info["service_tag"],  # Dell uses service tag as serial
        serial_number: info["service_tag"],
        firmware_version: info["firmware_version"],
        idrac_version: info["idrac_version"],
        is_dell: info["is_dell"]
      }.compact
    end
    
    # Individual accessor methods for Core::System interface
    def service_tag
      @service_tag ||= @idrac_client.system_info["service_tag"]
    end
    
    def make
      "Dell"
    end
    
    def model
      @model ||= begin
        model = @idrac_client.system_info["model"]
        model&.gsub(/^PowerEdge\s+/i, '') if model  # Strip PowerEdge prefix
      end
    end
    
    def serial
      @serial ||= @idrac_client.system_info["service_tag"]  # Dell uses service tag as serial
    end
    
    def cpus
      # The idrac gem returns a summary hash, but radfish expects an array of CPU objects
      # For Dell servers, typically all CPUs are identical, so we create objects based on the summary
      cpu_summary = @idrac_client.cpus
      
      # Create CPU objects that support dot notation
      count = cpu_summary["count"] || 0
      return [] if count == 0
      
      # For each CPU socket, create an object
      # Dell typically has identical CPUs, so we use the summary data for each
      (1..count).map do |socket_num|
        OpenStruct.new(
          socket: socket_num,
          manufacturer: "Intel", # Dell servers typically use Intel
          model: cpu_summary["model"],
          speed_mhz: nil, # Not provided in summary
          cores: cpu_summary["cores"] ? (cpu_summary["cores"] / count) : nil,
          threads: cpu_summary["threads"] ? (cpu_summary["threads"] / count) : nil,
          health: cpu_summary["status"]
        )
      end
    end
    
    def memory
      mem_data = @idrac_client.memory
      return [] unless mem_data
      
      # Convert to OpenStruct for dot notation access
      mem_data.map { |m| OpenStruct.new(m) }
    end
    
    def nics
      nic_data = @idrac_client.nics
      return [] unless nic_data
      
      # Convert to OpenStruct for dot notation access, including nested ports
      nic_data.map do |nic|
        if nic["ports"]
          nic["ports"] = nic["ports"].map { |port| OpenStruct.new(port) }
        end
        OpenStruct.new(nic)
      end
    end
    
    def fans
      # Convert hash array to OpenStruct objects for dot notation access
      fan_data = @idrac_client.fans
      
      fan_data.map do |fan|
        OpenStruct.new(fan)
      end
    end
    
    def temperatures
      # iDRAC doesn't provide a dedicated temperatures method
      # Return empty array to satisfy the interface
      []
    end
    
    def psus
      # Convert hash array to OpenStruct objects for dot notation access
      psu_data = @idrac_client.psus
      
      psu_data.map do |psu|
        OpenStruct.new(psu)
      end
    end
    
    def power_consumption
      # Return a hash with power consumption data for radfish
      {
        consumed_watts: @idrac_client.get_power_usage_watts
      }
    end
    
    def power_consumption_watts
      @idrac_client.get_power_usage_watts
    end
    
    # Storage
    
    def storage_controllers
      # Convert hash array to OpenStruct objects for dot notation access
      # Note: idrac gem uses 'controllers' not 'storage_controllers'
      controller_data = @idrac_client.controllers
      
      controller_data.map do |controller|
        # Promote battery status if available in OEM fields
        begin
          battery = controller.dig("Oem", "Dell", "DellControllerBattery")
          if battery
            controller["battery_status"] ||= (battery["PrimaryStatus"] || battery["RAIDState"]) 
          end
        rescue => e
          debug "Battery status parse error: #{e.message}", 2, :yellow
        end
        # Convert drives array to OpenStruct objects if present
        if controller["drives"]
          controller["drives"] = controller["drives"].map { |drive| OpenStruct.new(drive) }
        end
        OpenStruct.new(controller)
      end
    end
    
    def drives(controller)
      # The iDRAC gem requires a controller identifier; derive it from the controller
      raise ArgumentError, "Controller required" unless controller
      controller_id = extract_controller_identifier(controller)
      raise ArgumentError, "Controller identifier missing" unless controller_id
      
      drive_data = @idrac_client.drives(controller_id)
      
      # Convert to OpenStruct for consistency
      drive_data.map { |drive| OpenStruct.new(drive) }
    end
    
    def volumes(controller)
      # The iDRAC gem requires a controller identifier; derive it from the controller
      raise ArgumentError, "Controller required" unless controller
      controller_id = extract_controller_identifier(controller)
      raise ArgumentError, "Controller identifier missing" unless controller_id
      
      volume_data = @idrac_client.volumes(controller_id)
      
      # Convert to OpenStruct for consistency
      volume_data.map { |volume| OpenStruct.new(volume) }
    end

    def volume_drives(volume)
      # Resolve the physical drives that make up a volume
      raise ArgumentError, "Volume required" unless volume
      controller_id = extract_controller_identifier(volume.controller)
      # Get all drives on the controller
      drives = @idrac_client.drives(controller_id)
      # The IDRAC client drive entries include 'odata_id'; volumes include Links.Drives as '@odata.id'
      refs = nil
      raw = volume.adapter_data
      if raw.respond_to?(:[])
        refs = raw['drives'] || raw[:drives]
      elsif raw.respond_to?(:drives)
        refs = raw.drives
      end
      return [] unless refs && refs.respond_to?(:map)
      ref_ids = refs.map { |r| r['@odata.id'] || r[:'@odata.id'] }.compact
      matched = drives.select do |d|
        oid = if d.is_a?(Hash)
                d['odata_id'] || d[:odata_id] || d['@odata.id'] || d[:'@odata.id']
              elsif d.respond_to?(:[])
                d['odata_id'] || d['@odata.id']
              end
        oid && ref_ids.include?(oid)
      end
      matched.map { |drive| OpenStruct.new(drive) }
    end
    
    def storage_summary
      # The iDRAC gem doesn't have a storage_summary method
      # We need to build it from controllers, drives, and volumes
      begin
        controllers = @idrac_client.controllers
        total_drives = 0
        total_volumes = 0
        
        controllers.each do |controller|
          if controller["@odata.id"]
            drives = @idrac_client.drives(controller["@odata.id"]) rescue []
            volumes = @idrac_client.volumes(controller["@odata.id"]) rescue []
            total_drives += drives.size
            total_volumes += volumes.size
          end
        end
        
        {
          "controller_count" => controllers.size,
          "drive_count" => total_drives,
          "volume_count" => total_volumes
        }
      rescue => e
        puts "Error fetching storage summary: #{e.message}" if @debug
        {
          "controller_count" => 0,
          "drive_count" => 0,
          "volume_count" => 0
        }
      end
    end

    private

    def extract_controller_identifier(controller)
      # Prefer vendor-native handle from adapter_data
      raw = controller.respond_to?(:adapter_data) ? controller.adapter_data : controller
      if defined?(OpenStruct) && raw.is_a?(OpenStruct)
        table = raw.instance_variable_get(:@table)
        table && (table[:"@odata.id"] || table["@odata.id"]) || controller.id
      elsif raw.respond_to?(:[])
        raw['@odata.id'] || raw[:'@odata.id'] || controller.id
      else
        controller.id
      end
    end

    public
    
    # Virtual Media
    
    def virtual_media
      @idrac_client.virtual_media
    end
    
    def insert_virtual_media(iso_url, device: nil)
      # Default to "CD" for iDRAC if not specified
      device ||= "CD"
      @idrac_client.insert_virtual_media(iso_url, device: device)
    rescue Idrac::Error => e
      # Translate iDRAC errors to Radfish errors with context
      error_message = e.message
      
      if error_message.include?("connection refused") || error_message.include?("unreachable")
        raise Radfish::VirtualMediaConnectionError, "BMC cannot reach ISO server: #{error_message}"
      elsif error_message.include?("already attached") || error_message.include?("in use")
        raise Radfish::VirtualMediaBusyError, "Virtual media device busy: #{error_message}"
      elsif error_message.include?("not found") || error_message.include?("does not exist")
        raise Radfish::VirtualMediaNotFoundError, "Virtual media device not found: #{error_message}"
      elsif error_message.include?("timeout")
        raise Radfish::TaskTimeoutError, "Virtual media operation timed out: #{error_message}"
      else
        # Generic virtual media error
        raise Radfish::VirtualMediaError, error_message
      end
    rescue StandardError => e
      # Catch any other errors and wrap them
      raise Radfish::VirtualMediaError, "Virtual media insertion failed: #{e.message}"
    end
    
    def eject_virtual_media(device: "CD")
      @idrac_client.eject_virtual_media(device: device)
    rescue Idrac::Error => e
      if e.message.include?("not found") || e.message.include?("does not exist")
        raise Radfish::VirtualMediaNotFoundError, "Virtual media device not found: #{e.message}"
      else
        raise Radfish::VirtualMediaError, "Failed to eject virtual media: #{e.message}"
      end
    rescue StandardError => e
      raise Radfish::VirtualMediaError, "Failed to eject virtual media: #{e.message}"
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
    
    def boot_config
      # Return hash for consistent data structure
      @idrac_client.boot_config
    end
    
    # Shorter alias for convenience
    def boot
      boot_config
    end
    
    def boot_options
      # Return array of OpenStructs for boot options
      options = @idrac_client.boot_options
      options.map { |opt| OpenStruct.new(opt) }
    end
    
    def set_boot_override(target, enabled: "Once", mode: nil)
      @idrac_client.set_boot_override(target, enabled: enabled, mode: mode)
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
    
    def boot_to_pxe(enabled: "Once", mode: nil)
      @idrac_client.boot_to_pxe(enabled: enabled, mode: mode)
    end
    
    def boot_to_disk(enabled: "Once", mode: nil)
      @idrac_client.boot_to_disk(enabled: enabled, mode: mode)
    end
    
    def boot_to_cd(enabled: "Once", mode: nil)
      @idrac_client.boot_to_cd(enabled: enabled, mode: mode)
    end
    
    def boot_to_usb(enabled: "Once", mode: nil)
      @idrac_client.boot_to_usb(enabled: enabled, mode: mode)
    end
    
    def boot_to_bios_setup(enabled: "Once", mode: nil)
      @idrac_client.boot_to_bios_setup(enabled: enabled, mode: mode)
    end
    
    # PCI Devices
    
    def pci_devices
      devices = @idrac_client.pci_devices
      return [] unless devices
      
      # Convert to OpenStruct for dot notation access
      devices.map { |device| OpenStruct.new(device) }
    end
    
    def nics_with_pci_info
      nics = @idrac_client.nics
      pci = pci_devices
      
      # Use the existing nics_to_pci method from idrac gem
      nics_with_pci = @idrac_client.nics_to_pci(nics, pci.map(&:to_h))
      
      # Convert to OpenStruct
      nics_with_pci.map { |nic| OpenStruct.new(nic) }
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
    
    def clear_jobs!
      @idrac_client.clear_jobs!
    end
    
    def jobs_summary
      jobs
    end
    
    # BMC Management
    
    def ensure_vendor_specific_bmc_ready!
      # For iDRAC, ensure the Lifecycle Controller is enabled
      @idrac_client.ensure_lifecycle_controller!
    end
    
    # BIOS Configuration
    
    def bios_error_prompt_disabled?
      @idrac_client.bios_error_prompt_disabled?
    end
    
    def bios_hdd_placeholder_enabled?
      @idrac_client.bios_hdd_placeholder_enabled?
    end
    
    def bios_os_power_control_enabled?
      @idrac_client.bios_os_power_control_enabled?
    end
    
    def ensure_uefi_boot
      @idrac_client.ensure_uefi_boot
    end
    
    def set_one_time_boot_to_virtual_media
      # Use iDRAC's existing method for setting one-time boot to virtual media
      @idrac_client.set_one_time_virtual_media_boot
    end
    
    def set_boot_order_hd_first
      # Use iDRAC's existing method for setting boot order to HD first
      @idrac_client.set_boot_order_hd_first
    end
    
    def ensure_sensible_bios!(options = {})
      # Check current state
      if bios_error_prompt_disabled? && 
         bios_hdd_placeholder_enabled? && 
         bios_os_power_control_enabled?
        puts "BIOS settings already configured correctly".green
        return { changes_made: false }
      end
      
      puts "Configuring BIOS settings...".yellow
      
      # Build the System Configuration Profile (SCP)
      scp = {}
      
      # Disable error prompt (don't halt on errors)
      if !bios_error_prompt_disabled?
        scp = @idrac_client.merge_scp(scp, {
          "BIOS.Setup.1-1" => {
            "ErrPrompt" => "Disabled"
          }
        })
      end
      
      # Enable HDD placeholder for boot order control
      if !bios_hdd_placeholder_enabled?
        scp = @idrac_client.merge_scp(scp, {
          "BIOS.Setup.1-1" => {
            "HddPlaceholder" => "Enabled"
          }
        })
      end
      
      # Enable OS power control
      if !bios_os_power_control_enabled?
        scp = @idrac_client.merge_scp(scp, {
          "BIOS.Setup.1-1" => {
            "ProcCStates" => "Enabled",
            "SysProfile" => "PerfPerWattOptimizedOs",
            "ProcPwrPerf" => "OsDbpm"
          }
        })
      end
      
      # Set UEFI boot mode
      scp = @idrac_client.merge_scp(scp, {
        "BIOS.Setup.1-1" => {
          "BootMode" => "Uefi"
        }
      })
      
      # Disable host header check for better compatibility
      scp = @idrac_client.merge_scp(scp, {
        "iDRAC.Embedded.1" => {
          "WebServer.1#HostHeaderCheck" => "Disabled"
        }
      })
      
      # Apply the configuration
      @idrac_client.set_system_configuration_profile(scp)
      
      { changes_made: true }
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
    
    def bmc_info
      # Map iDRAC gem data to radfish format
      info = {}
      
      # Get firmware version from idrac gem
      info[:firmware_version] = @idrac_client.get_firmware_version
      
      # Get iDRAC generation (7/8/9) from idrac gem's license_version method
      info[:license_version] = @idrac_client.license_version&.to_s
      
      # Get Redfish version from idrac gem
      info[:redfish_version] = @idrac_client.redfish_version
      
      # Get network info for MAC and IP
      network = @idrac_client.get_bmc_network
      if network.is_a?(Hash)
        info[:mac_address] = network["mac"]
        info[:ip_address] = network["ipv4"]
        info[:hostname] = network["hostname"] || network["fqdn"]
      end
      
      # Get health status from system info
      system = @idrac_client.system_info
      if system.is_a?(Hash)
        info[:health] = system.dig("Status", "Health") || system.dig("Status", "HealthRollup")
      end
      
      info
    end
    
    def system_health
      # Convert hash to OpenStruct for dot notation access
      health_data = @idrac_client.system_health
      OpenStruct.new(health_data)
    end
    
    # Additional iDRAC-specific methods
    
    def screenshot
      @idrac_client.screenshot
    end
    
    def license_info
      @idrac_client.license_info
    end
    
    # Network management
    
    def get_bmc_network
      @idrac_client.get_bmc_network
    end
    
    def set_bmc_network(ipv4: nil, mask: nil, gateway: nil, 
                        dns_primary: nil, dns_secondary: nil, hostname: nil, 
                        dhcp: false)
      @idrac_client.set_bmc_network(
        ipv4: ipv4,
        mask: mask,
        gateway: gateway,
        dns_primary: dns_primary,
        dns_secondary: dns_secondary,
        hostname: hostname,
        dhcp: dhcp
      )
    end
    
    def set_bmc_dhcp
      @idrac_client.set_bmc_dhcp
    end
  end
  
  # Register the adapter
  Radfish.register_adapter('dell', IdracAdapter)
  Radfish.register_adapter('idrac', IdracAdapter)
end
