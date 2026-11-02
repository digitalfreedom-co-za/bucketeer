#!/usr/bin/env ruby
# Adds the "BucketeerTests" unit-test bundle (host view-render and flow
# tests). Idempotent — re-running is a no-op once the target exists.
#
# The bundle has no test host: it compiles the host sources itself
# (everything in Bucketeer/ except the @main App file), so running the
# tests never launches Bucketeer.app.
#
# Usage: ruby scripts/add_test_target.rb

require 'xcodeproj'

PROJECT = 'Bucketeer.xcodeproj'
NAME = 'BucketeerTests'
BUNDLE_ID = 'za.co.digitalfreedom.BucketeerTests'
TEAM = '7TSZJCJY88'
SHARED_FAKE = 'BucketeerCore/Tests/BucketeerCoreTests/Support/InMemoryS3Browser.swift'
HOST_ONLY = %w[Info.plist App/BucketeerApp.swift]

proj = Xcodeproj::Project.open(PROJECT)
host = proj.targets.find { |t| t.name == 'Bucketeer' }
raise 'host target not found' unless host
if proj.targets.any? { |t| t.name == NAME }
  puts "target '#{NAME}' already exists — nothing to do"
  exit 0
end

tests = proj.new_target(:unit_test_bundle, NAME, :osx, '14.0', proj.products_group, :swift)
tests.build_configurations.each do |cfg|
  s = cfg.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['DEVELOPMENT_TEAM'] = TEAM
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  s['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  s['SWIFT_VERSION'] = '6.0'
  s['SWIFT_APPROACHABLE_CONCURRENCY'] = 'YES'
  s['SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY'] = 'YES'
  s['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  s['STRING_CATALOG_GENERATE_SYMBOLS'] = 'YES'
  s['LOCALIZATION_PREFERS_STRING_CATALOGS'] = 'YES'
  s['ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS'] = 'YES'
  s.delete('TEST_HOST')
  s.delete('BUNDLE_LOADER')
end

# Host sources and resources, minus the app entry point.
host_group = proj.root_object.main_group.children.find do |c|
  c.isa == 'PBXFileSystemSynchronizedRootGroup' && c.path == 'Bucketeer'
end
raise 'synchronized Bucketeer group not found' unless host_group
exceptions = proj.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
exceptions.target = tests
exceptions.membership_exceptions = HOST_ONLY
host_group.exceptions << exceptions
tests.file_system_synchronized_groups << host_group

# The test sources themselves.
test_group = proj.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
test_group.path = NAME
test_group.source_tree = '<group>'
proj.root_object.main_group.children << test_group
tests.file_system_synchronized_groups << test_group

# In-memory S3Browsing fake shared with the Core tests.
fake_ref = proj.root_object.main_group.new_reference(SHARED_FAKE)
tests.source_build_phase.add_file_reference(fake_ref)

host.package_product_dependencies.each do |dep|
  tests.package_product_dependencies << dep
  build_file = proj.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dep
  tests.frameworks_build_phase.files << build_file
end

proj.save
puts "added target '#{NAME}'"
