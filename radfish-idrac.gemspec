# frozen_string_literal: true

require_relative "lib/radfish/idrac/version"

Gem::Specification.new do |spec|
  spec.name = "radfish-idrac"
  spec.version = Radfish::Idrac::VERSION
  spec.authors = ["Jonathan Siegel"]
  spec.email = ["jonathan@buildio.co"]

  spec.summary = "Dell iDRAC adapter for Radfish"
  spec.description = "Provides Dell iDRAC support for the Radfish unified Redfish client"
  spec.homepage = "https://github.com/buildio/radfish-idrac"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{lib}/**/*", "LICENSE", "README.md"]
  end

  spec.require_paths = ["lib"]

  spec.add_dependency "radfish", "~> 0.1"
  spec.add_dependency "idrac", "~> 0.8"
  
  spec.add_development_dependency "rspec", "~> 3.0"
end