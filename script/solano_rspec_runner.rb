# Rspec test runner for Solano CI parallel junit test type
# http://docs.solanolabs.com/ConfiguringLanguage/java/#parallel-junit
#
# 1. Ensure arguments (test files) were supplied and match existing files
# 2. Run assigned tests (arguments for script) with Junit formatter.
# 3. After the rspec process is complete, consider the exit code and generated XML file to determine:
#    a. Did the test files actually run (catch syntax errors, broken 'require', 'nil' methods, etc.)?
#       If not, add fail reason to all tests in batch.
#    b. Did all of the assigned tests produce output?
#       If some tests were skipped/pending, add relevant '<testcase/>' nodes to XML file
# (not sure yet): Change '<testcase file=""/>' attributes in XML file???
# 4. Copy the generated XML files to a location where they will be added as build artifacts:
#    http://docs.solanolabs.com/Setup/interacting-with-build-environment/#using-a-post-worker-hook
# To implement later?
#   1. Instead of running command in a subshell, run in-process
#   2. Enforce a timeout so at least partial results are reported to Solano CI
#   3. Compare individual test results to previous build(s) to identify "suspicious" test behavior:
#      a. Test was skipped when it typically isn't
#      b. Test time was 
# 
# set -o errexit -o pipefail # Exit on error
#      bundle exec rspec  --format RspecJunitFormatter  --out reports/$TDDIUM_TEST_EXEC_ID-rspec.xml $@
#      if ls reports/*-rspec.xml; then
#        cp reports/*-rspec.xml $HOME/results/$TDDIUM_SESSION_ID/session/
#      fi

require 'pathname'
require 'fileutils'
require 'open3'
require 'nokogiri'

REPORTS_DIR="reports"
REPORT_SUFFIX="-rspec.xml"

# Ensure arguments (test files) were supplied
if ARGV.length == 0 then
  $stderr.puts "ERROR: No test files listed as arguments"
  $stderr.puts "Usage: #{__FILE__} test_file [test_file ...]"
  Kernel.exit(1)
end

# Ensure arguments are test files
files_exist = true
for i in 0 ... ARGV.length
  pn = Pathname.new(ARGV[i])
  if ! pn.file? then
    $stderr.puts "ERROR: '#{ARGV[i]}' is not an existing file"
    files_exist = false
  end
end
if ! files_exist then
  $stderr.puts "ERROR: One or more supplied arguments were not existing files"
  Kernel.exit(2)
end

def on_solano?
  ! ENV['TDDIUM'].nil?
end

# Ruby hashes are much easier to deal with then nokogiri objects
#class Nokogiri::XML::Node
#  TYPENAMES = {1=>'element',2=>'attribute',3=>'text',4=>'cdata',8=>'comment'}
#  def to_hash
#    {kind:TYPENAMES[node_type],name:name}.tap do |h|
#      h.merge! nshref:namespace.href, nsprefix:namespace.prefix if namespace
#      h.merge! text:text
#      h.merge! attr:attribute_nodes.map(&:to_hash) if element?
#      h.merge! kids:children.map(&:to_hash) if element?
#    end
#  end
#end
#class Nokogiri::XML::Document
#  def to_hash; root.to_hash; end
#end

# Give Junit XML files a unique name
@xml_report_id = on_solano? ? ENV['TDDIUM_TEST_EXEC_ID_LIST'].split(",").first : Time.now.to_f.to_s
@xml_report_file = "#{@xml_report_id}#{REPORT_SUFFIX}"

# Run the assigned tests with preferred+required arguments (modify as needed)
#cmd = `rspec --order defined --backtrace --color --tty --format RspecJunitFormatter --out #{File.join(REPORTS_DIR, @xml_report_file)} #{ARGV.join(" ")}`
#exit_status = $?.exitstatus
@cmd = "rspec --order defined --backtrace --color --tty --format RspecJunitFormatter --out #{File.join(REPORTS_DIR, @xml_report_file)} "
# Add test files to command
@cmd << ARGV.join(" ")
Open3.popen3(@cmd) do |stdin, stdout, stderr, wait_thr|
  @cmd_out = stdout.read
  @cmd_err = stderr.read
  @cmd_status = wait_thr.value.exitstatus
end

# The existence of a non-zero-byte generated Junit XML file indicates 'cmd' didn't insta-fail from a syntax error, undefined method/varialbe, etc.
if ! File.size?(File.join(REPORTS_DIR, @xml_report_file)).nil? then
  junit_doc = File.open(File.join(REPORTS_DIR, @xml_report_file)) { |f| Nokogiri::XML(f) }
else
  junit_doc = Nokogiri::XML::Builder.new do |xml|
    xml.
  end
end


  # Test files that were marked pending/skipped may not be included in the Junit XML
  missing_test_files = []
  # Read Junit XML
  
  for i in 0 ... ARGV.length
    test_file = ARGV[i]
    # RspecJunitFormatter adds a './' to test file names
    test_file_attr = "./#{test_file}"
    if ! junit_doc.xpath("//testsuite/testcase[@file='#{test_file_attr}']").any? then
      missing_test_files.push(test_file)
    end
  end
  # If any test files were not included, add appropriate XML nodes
  if missing_test_files.any? then
    missing_test_files.each do |test_file|
      system_out = Nokogiri::XML::Node.new('system-out', junit_doc)
      system_out.content = "#{test_file} did not report output, marked as skipped"
      skipped = Nokogiri::XML::Node.new('skipped', junit_doc)
      testcase = Nokogiri::XML::Node.new('testcase', junit_doc)
      testcase['classname'] = test_file.gsub(/.rb$/, '').gsub('/', '.') # To make consistent with RspecJunitFormatter
      testcase['name'] = "SKIPPED: #{test_file}"
      testcase['file'] = "./#{test_file}" # RspecJunitFormatter adds a './' to test file names
      testcase['time'] = "0"
      testcase << system_out
      testcase << skipped
      junit_doc.xpath("//testsuite").first.add_child(testcase)
    end
  end
  # Include command as <property/> node
  cmd_node = Nokogiri::XML::Node.new('property', junit_doc)
  cmd_node['name'] = "command"
  cmd_node['value'] = @cmd

  # Write changed XML back to report file
  File.write(File.join(REPORTS_DIR, @xml_report_file), junit_doc.to_xml)
else
  # No Junit XML report file was generated or was zero bytes. 
  if @cmd_status == 0 then
    puts "all skipped"
    put cmd.inspect
    # rspec command succedded, create XML file with all skips
  else
    puts "all failed with #{@cmd_status}"
    put cmd.inspect
    # rspec command failed, create XML file with all failures
  end
end

if on_solano? then
  # Attach relevant files as build artifacts
  artifacts_dir = File.join(ENV['HOME'], "results", ENV['TDDIUM_SESSION_ID'], "session")
  if File.exist?(File.join(REPORTS_DIR, @xml_report_file)) then
    FileUtils.cp File.join(REPORTS_DIR, @xml_report_file), File.join(artifacts_dir, @xml_report_file)
  end
  `echo #{@cmd_status} > #{File.join(artifacts_dir, "#{@xml_report_id}-exit_status.txt")}`
  `env | sort > #{File.join(artifacts_dir, "#{@xml_report_id}-env.txt")}`
end

Kernel.exit(@cmd_status)