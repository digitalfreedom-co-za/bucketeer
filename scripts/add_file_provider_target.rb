#!/usr/bin/env ruby
# Adds the "Bucketeer File Provider" app-extension target to the Xcode
# project (Phase 9). Idempotent — re-running is a no-op once the target
# exists. Replaces the manual pbxproj surgery PHASE_9_SETUP.md warned
# about; the xcodeproj gem keeps the file internally consistent.
#
# Usage: ruby scripts/add_file_provider_target.rb

require 'xcodeproj'

PROJECT = 'Bucketeer.xcodeproj'
EXT_NAME = 'Bucketeer File Provider'
EXT_DIR = 'Bucketeer File Provider'
BUNDLE_ID = 'za.co.digitalfreedom.Bucketeer.FileProvider'
TEAM = '7TSZJCJY88'
SOURCES = %w[
  ExtensionContainer.swift
  FileProviderEnumerator.swift
  FileProviderExtension.swift
  FileProviderItemResolver.swift
  S3DirectFetch.swift
]

proj = Xcodeproj::Project.open(PROJECT)
host = proj.targets.find { |t| t.name == 'Bucketeer' }
raise 'host target not found' unless host

if proj.targets.any? { |t| t.name == EXT_NAME }
  puts "target '#{EXT_NAME}' already exists — nothing to do"
  exit 0
end

ext = proj.new_target(
  :app_extension, EXT_NAME, :osx, '14.0', proj.products_group, :swift
)

# Build settings on both configurations.
ext.build_configurations.each do |cfg|
  s = cfg.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = "#{EXT_DIR}/Info.plist"
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = "#{EXT_DIR}/BucketeerFileProvider.entitlements"
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = TEAM
  s['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  s['SWIFT_VERSION'] = '6.0'
  s['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['SKIP_INSTALL'] = 'YES'
  s['ENABLE_HARDENED_RUNTIME'] = 'YES'
  s['CODE_SIGNING_ALLOWED'] = '$(CODE_SIGNING_ALLOWED)'
  s['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)', '@executable_path/../../../../Frameworks',
    '@executable_path/../../Frameworks'
  ]
end

# Source files: explicit references in a group for the extension folder.
group = proj.main_group.find_subpath(EXT_DIR, true)
group.set_source_tree('SOURCE_ROOT')
group.set_path(EXT_DIR)
SOURCES.each do |file|
  ref = group.find_file_by_path("#{EXT_DIR}/#{file}") ||
        group.new_reference("#{EXT_DIR}/#{file}")
  ext.add_file_references([ref])
end

# Link the same SPM products the host uses (SotoS3 remote, BucketeerCore local).
host.package_product_dependencies.each do |host_dep|
  dep = proj.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.product_name = host_dep.product_name
  dep.package = host_dep.package
  ext.package_product_dependencies << dep
  bf = proj.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = dep
  ext.frameworks_build_phase.files << bf
end

# Host depends on + embeds the extension.
host.add_dependency(ext)
embed = host.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(ext.product_reference, true)
bf.settings = { 'ATTRIBUTES' => %w[RemoveHeadersOnCopy] }

# Keep the embed phase before nothing critical; Xcode runs it after the
# extension builds because of the target dependency.

proj.save
puts "added target '#{EXT_NAME}' (#{BUNDLE_ID})"
puts "  sources: #{SOURCES.length}"
puts "  linked: #{ext.package_product_dependencies.map(&:product_name).join(', ')}"
puts "  host embeds: #{ext.product_reference.display_name}"
