# frozen_string_literal: true

require 'ostruct'

def parse_args(argv = ARGV)
  last = nil
  args = Hash.new(false)
  %w[help debug file index].each { |arg| args[arg] = false }
  args['files'] = []
  args['index_file'] = nil

  argv.each do |arg|
    if %w[file index].include?(last)
      args['files'] << arg if last == 'file'
      args['index_file'] = arg if last == 'index'
      last = nil
      next
    end

    arg2 = arg.gsub('--', '')
    case arg2
    when 'debug', 'help', 'file', 'index'
      args[arg2] = true
    else
      raise "Unknown argument '#{arg}'"
    end
    last = arg2
  end

  raise 'Cannot provide "file" and "index" arguments simultaneously. Pick one!' if args['file'] && args['index']

  return OpenStruct.new(args)
end
