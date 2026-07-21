# frozen_string_literal: true

require 'rspec/core/rake_task'

Dir.glob('tasks/*.rake').each { |f| load f }

task default: %i[test_js spec]
task test: %i[test_js spec] # Aliasing because it's easier than teaching my fingers to not type 'test'

task :initialize_config do # rubocop:disable Rake/Desc
  # Force lib onto the load path to match how it would run when packaged as a gem
  $LOAD_PATH.unshift './lib'

  require 'jirametrics'
  puts "Deprecated: This project is now packaged as the ruby gem 'jirametrics' and should be " \
    'called through that. See https://jirametrics.org'
end

desc 'Download data from Jira'
task download: %i[initialize_config] do
  JiraMetrics.start ['download']
end

desc 'Generate the reports'
task export: [:initialize_config] do
  JiraMetrics.start ['export']
end

desc 'Same as calling download and then export'
task go: %i[initialize_config download export]

desc 'info'
task info: [:initialize_config] do
  key = ARGV[1]
  raise 'Usage: rake info ISSUE_KEY  e.g. rake info SP-10' unless key

  ARGV[1..].each { |a| task(a.to_sym) {} } # rubocop:disable Rake/Desc
  JiraMetrics.start ['info', key]
end

desc 'stitch'
task stitch: [:initialize_config] do
  JiraMetrics.start %w[stitch]
end

RSpec::Core::RakeTask.new(:spec)

# Hang the confidentiality guard off :spec itself, so it fires however the specs are invoked
# -- `rake spec` directly, or via `test`/`default` which depend on spec -- rather than only
# on the aggregate tasks. enhance adds it as a prerequisite of the RSpec-defined task above.
Rake::Task[:spec].enhance([:check_confidentiality])

RSpec::Core::RakeTask.new(:focus) do |task, _args|
  task.rspec_opts = '--tag focus'
end

desc 'Run JavaScript tests'
task :test_js do
  sh 'npm test'
end

desc 'Run mutation tests (pass CLASS=ClassName to test a single class)'
task :mutant do
  subject = ENV['CLASS'] || '.mutant.yml subjects'
  puts "Running mutation tests against: #{subject}"
  if ENV['CLASS']
    sh "bundle exec mutant run --integration rspec -- '#{ENV['CLASS']}'"
  else
    sh 'bundle exec mutant run'
  end
end

namespace :mutant do
  desc 'Run mutation tests and append a survivors-by-method table (CLASS=ClassName to scope). ' \
       'Best-effort: mutant 0.16 has no structured/JSON reporter, so the table is parsed out of ' \
       'its text output. If a mutant upgrade ever changes that format the table may come up empty ' \
       '-- the run output above it is always the authoritative source.'
  task :report do
    require 'tempfile'

    subject = ENV.fetch('CLASS', nil)
    target = subject ? "-- '#{subject}'" : ''
    puts "Running mutation tests against: #{subject || '.mutant.yml subjects'}"

    log = Tempfile.new(['mutant', '.log'])
    # tee keeps the live run streaming to the terminal while we capture it for the tally. We
    # deliberately ignore the exit status: surviving mutants make mutant exit non-zero, and for a
    # report that's the normal case, not a failure -- we want the table, not an aborted rake run.
    system("bundle exec mutant run --integration rspec #{target} | tee #{log.path}")
    output = File.read(log.path).gsub(/\e\[[0-9;]*m/, '') # strip any ANSI colour before parsing
    log.close!

    # Mutant prints ONE representative survivor per subject as an "evil:<Subject>:..." line, then
    # summarises the rest as "(N more alive mutation(s), use `mutant session subject <Subject>` ...)".
    # So survivors-per-method = the one shown + N more. Counting only the evil: lines would tally
    # subjects-with-survivors, not survivors -- the bug this task's first cut actually had.
    counts = Hash.new(0)
    output.scan(%r{^evil:(.+?):/}).each { |(subject_name)| counts[subject_name] += 1 }
    output.scan(/\((\d+) more alive mutation\(s\), use `mutant session subject (\S+)`/).each do |(more, subject_name)|
      counts[subject_name] += more.to_i
    end
    survivors = counts.sort_by { |_subject, count| -count }

    puts
    puts '-' * 72
    if survivors.empty?
      puts 'No surviving mutations parsed (either 100% coverage, or the output format changed).'
    else
      puts "Survivors by method (#{survivors.sum { |_subject, count| count }} total), worst first:"
      survivors.each { |subject_name, count| printf("  %4<count>d  %<name>s\n", count: count, name: subject_name) }
    end
    puts '-' * 72
  end
end
