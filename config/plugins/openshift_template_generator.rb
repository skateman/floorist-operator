#!/bin/ruby

require 'yaml'

if ARGV[0].nil? || ARGV[1].nil?
  puts "Usage: #{$PROGRAM_NAME} parameters.yaml name_of_template"
  exit 1
end

objects = YAML.load_stream(STDIN)
parameters = YAML.safe_load(File.open(ARGV[0]))

template = {
  'apiVersion' => 'v1',
  'kind' => 'Template',
  'metadata' => {
    'name' => ARGV[1]
  },
  'objects' => objects,
  'parameters' => parameters
}

YAML.dump(template, STDOUT)
