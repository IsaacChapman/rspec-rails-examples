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

# Record XML file name
xml_report_file = "reports/#{Time.now.to_f}.xml"

# Run the assigned tests with preferred+required arguments:
cmd = `rspec --order defined --backtrace --color --tty --format RspecJunitFormatter --out #{xml_report_file} #{ARGV.join(" ")}`
exit_status = $?.exitstatus

if ! ENV['TDDIUM'].nil? && ENV['TDDIUM'].is_set? then
  FileUtils.cp xml_report_file, "#{ENV['HOME']}/results/#{ENV['TDDIUM_SESSION_ID']}/session/#{xml_report_file}"
  # TEMP
  `env | sort > #{ENV['HOME']}/results/#{ENV['TDDIUM_SESSION_ID']}/session/#{xml_report_file}-env.txt`
end

Kernel.exit(exit_status)