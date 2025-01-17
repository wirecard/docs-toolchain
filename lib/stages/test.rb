# frozen_string_literal: true

require 'thread/pool'
require_relative '../cli.rb'
require_relative '../config_manager.rb'
require_relative '../extension_manager.rb'
require_relative '../log/log.rb'
require_relative '../utils/adoc.rb'
require_relative '../utils/paths.rb'

# require extensions
Dir[
  File.join(__dir__, '../', 'extensions.d', '*.rb')
].sort.each { |file| require file }
Dir[
  File.join(::Toolchain.custom_dir, 'extensions.d', '*.rb')
].sort.each { |file| require file }

##
# hash to cache all filename: converted_adoc pairs
ADOC_MAP = Hash.new(nil)
##
# default index file
DEFAULT_INDEX = Toolchain::ConfigManager.instance.get('asciidoc.index.file')
##
# Mutex
MUTEX = Mutex.new

##
# represents a pair of parsed, resolved adoc and original adoc
# Params:
# * +original+: original adoc source code before conversion
# * +parsed+: parsed adoc source code
# * +attributes+: attributes of document
#
Entry = Struct.new(:original, :parsed, :attributes) do
  private

  def original=; end

  def parsed=; end

  def attributes=; end
end

##
# print help
# print all loaded extensions
def print_loaded_extensions
  log('TESTING', 'loaded extensions:')
  Toolchain::ExtensionManager.instance.get.each do |ext|
    log('EXT', ext.class.name)
  end
end

##
# Print all errors in +errors_map+.
# +errors_map+ is a hash containing a mapping of filename -> [errors].
# Format: "id message"
#
# Returns +nil+.
#
def print_errors(errors_map)
  num_errors = 0
  errors_map.each do |_file, errors|
    num_errors += errors.length
  end
  gh_style = ENV['GITHUB_ACTIONS'] == 'true' && num_errors <= 10
  puts '::warning::More than 10 errors found, please check Build log' if ENV['GITHUB_ACTIONS'] == 'true' &&
      num_errors > 10 &&
      errors_map.length > 1 # skip for single file index.adoc

  errors_map.each do |file, errors|
    # TODO: decide whether index only errors are possible and index.adoc should be included after all
    next if file == 'index.adoc'

    gh_style || log('ERRORS', "for file #{file}", :red) unless errors.empty?
    errors.each do |err|
      # TODO: do all this in logger class in log.rb
      if(gh_style)
        # github actions format echo "::warning file=app.js,line=1,col=5::Missing semicolon"
        puts "::warning file=#{file}::#{err[:msg]}"
      else
        puts "#{err[:id]}\t#{err[:msg]}".bold.red
      end
    end
  end
end

##
# Run all extensions registered with +ExtensionManager+ on the file +filename+.
#
# During this process, the file +filename+ will be loaded, converted and cached
# in +ADOC_MAP+.
#
# Returns +errors+ for the given file.
def run_tests(filename)
  if ADOC_MAP[filename].nil?

    adoc = Toolchain::Adoc.load_doc(filename,
      'root' => ::Toolchain.document_root
    )
    original = adoc.original
    parsed = adoc.parsed
    attributes = adoc.attributes

    entry = Entry.new(original: original, parsed: parsed, attributes: attributes)
    ADOC_MAP[filename] = entry
  else
    entry = ADOC_MAP[filename]
    parsed = entry.parsed
    original = entry.original
    attributes = entry.attributes
  end

  errors = []
  Toolchain::ExtensionManager.instance.get.each do |ext|
    result = ext.run(adoc)
    errors += result if result.is_a?(Array)
  end
  return errors
end

##
# Check all included files in for a given index.
#
# All include files +included_files+ in +content_dir+ will be checked.
# This means each file will be tested with +run_tests+.
#
# Returns a map of +errors_map+ with schema filename => [errors].
def check_docs(included_files, content_dir)
  errors_map = {}
  size = 32
  log('THREADING', "Pool size: #{size}")
  pool = Thread.pool(size)

  paths = included_files.map { |f, _| "#{File.join(content_dir, f)}.adoc" }
  paths.each do |f|
    pool.process do
      next if f =~%r{^./include/}
      #log('INCLUDE', "Testing #{f}")
      errors = run_tests(f)
      MUTEX.synchronize do
        errors_map[f] = errors
      end
    end
  end

  pool.shutdown
  return errors_map
end

