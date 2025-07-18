#!/usr/bin/env ruby
require_relative 'config/environment'

# Test case-insensitive uniqueness validation
puts "Testing case-insensitive uniqueness validation..."

# Clean up any existing test data
Host.where(name: ['test.com', 'Test.com', 'TEST.com']).destroy_all

# Create first host
host1 = Host.create!(name: 'test.com', url: 'https://test.com', kind: 'git')
puts "Created host1: #{host1.name}"

# Try to create host with different case
host2 = Host.new(name: 'Test.com', url: 'https://test.com', kind: 'git')
if host2.valid?
  puts "ERROR: host2 should not be valid!"
  exit 1
else
  puts "SUCCESS: host2 is invalid as expected"
  puts "Errors: #{host2.errors.full_messages}"
end

# Try to create host with uppercase
host3 = Host.new(name: 'TEST.com', url: 'https://test.com', kind: 'git')
if host3.valid?
  puts "ERROR: host3 should not be valid!"
  exit 1
else
  puts "SUCCESS: host3 is invalid as expected"
  puts "Errors: #{host3.errors.full_messages}"
end

# Clean up
host1.destroy
puts "Validation test completed successfully!"