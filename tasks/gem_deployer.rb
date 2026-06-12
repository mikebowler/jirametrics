# frozen_string_literal: true

require 'net/http'
require 'json'
require 'open3'
require 'tempfile'

# OTP = One Time Password

class GemDeployer
  RUBYGEMS_VERSIONS_URL = 'https://rubygems.org/api/v1/versions/jirametrics.json'
  OTP_INCORRECT_PATTERN = 'incorrect'

  def initialize gemspec_path: 'jirametrics.gemspec', changes_path: '../jekyll_jirametrics/changes.md'
    @gemspec_path = gemspec_path
    @changes_path = changes_path
  end

  def run
    puts "Deploying jirametrics #{current_version}..."
    puts ''

    verify_git_clean
    verify_stable_version
    verify_newer_than_deployed
    verify_changelog_entry

    gem_file = build_gem
    otp = prompt_otp
    push_gem gem_file, otp
    install_gem gem_file
    File.delete gem_file

    otp = yank_prereleases otp
    create_github_release otp

    puts ''
    puts "Release #{current_version} complete!"
  end

  def build_and_install
    gem_file = build_gem
    install_gem gem_file
    puts gem_file
  end

  def run_prerelease
    verify_no_uncommitted_changes

    new_version_str = calculate_prerelease_version

    print "New version is #{new_version_str}. Proceed? (y/n): "
    answer = $stdin.gets.strip.downcase
    raise 'Aborted.' unless answer == 'y'

    if new_version_str != gemspec_version_string
      update_gemspec_version(new_version_str)
      commit_and_push_version(new_version_str)
    end

    puts "Deploying jirametrics #{current_version} (pre-release)..."
    puts ''

    verify_prerelease_version

    gem_file = build_gem
    otp = prompt_otp
    push_gem gem_file, otp
    install_gem gem_file
    File.delete gem_file

    yank_prereleases otp

    puts ''
    puts "Pre-release #{current_version} complete!"
  end

  def current_version
    @current_version ||= Gem::Specification.load(@gemspec_path).version
  end

  def changelog_section
    @changelog_section ||= begin
      content = File.read(@changes_path)
      content = content.sub(/\A---\n.*?---\n/m, '')
      content.split(/^(?=# v)/).find { |s| s.start_with? "# v#{current_version} " }
    end
  end

  def release_notes
    return '' unless changelog_section

    changelog_section
      .sub(/^# v.*\n/, '')
      .strip
      .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
  end

  def prereleases_to_yank
    previous_stable = deployed_stable_versions.first
    rubygems_versions
      .select { |v| v[:prerelease] }
      .map { |v| v[:version] }
      .select { |v| previous_stable.nil? || v > previous_stable }
      .reject { |v| v == current_version }
  end

  private

  def rubygems_versions
    @rubygems_versions ||= begin
      uri = URI(RUBYGEMS_VERSIONS_URL)
      response = Net::HTTP.get(uri)
      JSON.parse(response).map do |v|
        { version: Gem::Version.new(v['number']), prerelease: v['prerelease'] }
      end
    end
  end

  def deployed_stable_versions
    rubygems_versions
      .reject { |v| v[:prerelease] }
      .map { |v| v[:version] }
      .sort.reverse
  end

  def verify_git_clean
    verify_no_uncommitted_changes

    print 'Checking for unpushed commits... '
    unpushed = `git log origin/main..HEAD --oneline`.strip
    raise "\nUnpushed commits exist. Please push first." unless unpushed.empty?

    puts 'OK'
  end

  def verify_no_uncommitted_changes
    print 'Checking for uncommitted changes... '
    uncommitted = `git status --porcelain`.strip
    raise "\nUncommitted changes exist. Please commit first." unless uncommitted.empty?

    puts 'OK'
  end

  def verify_stable_version
    print "Checking version #{current_version} is a stable release... "
    raise "\n#{current_version} is a pre-release. This task is for stable releases only." if current_version.prerelease?

    puts 'OK'
  end

  def verify_prerelease_version
    print "Checking version #{current_version} is a pre-release... "
    unless current_version.prerelease?
      raise "\n#{current_version} is a stable release. This task is for pre-releases only."
    end

    puts 'OK'
  end

  def verify_newer_than_deployed
    print 'Checking version is newer than what is deployed... '
    latest = deployed_stable_versions.first
    if latest && current_version <= latest
      raise "\n#{current_version} is not newer than the currently deployed version #{latest}"
    end

    puts "OK (currently deployed: #{latest || 'none'})"
  end

  def verify_changelog_entry
    print "Checking changes.md has an entry for v#{current_version}... "
    raise "\nNo entry for v#{current_version} found in #{@changes_path}" if changelog_section.nil?

    puts 'OK'
  end

  def build_gem
    puts 'Building gem...'
    system('gem build jirametrics.gemspec') || raise('gem build failed')
    "jirametrics-#{current_version}.gem"
  end

  def prompt_otp
    print "\nEnter OTP code for rubygems.org: "
    $stdin.gets.strip
  end

  def push_gem gem_file, otp
    puts "Pushing #{gem_file} to RubyGems..."
    stdout, stderr, status = Open3.capture3("gem push #{gem_file} --otp #{otp}")
    print stdout
    raise "gem push failed:\n#{stderr}" unless status.success?
  end

  def install_gem gem_file
    puts "Installing #{gem_file} locally..."
    system("gem install #{gem_file}") || raise('gem install failed')
  end

  def yank_prereleases otp
    versions = prereleases_to_yank
    if versions.empty?
      puts 'No pre-releases to yank.'
      return otp
    end

    puts "Yanking #{versions.size} pre-release(s): #{versions.join(', ')}"
    versions.each do |version|
      otp = yank_version version, otp
    end
    otp
  end

  def yank_version version, otp
    print "  Yanking #{version}... "
    stdout, _stderr, status = Open3.capture3("gem yank jirametrics -v #{version} --otp #{otp}")

    if !status.success? && stdout.include?(OTP_INCORRECT_PATTERN)
      puts 'OTP expired.'
      otp = prompt_otp
      stdout, _stderr, status = Open3.capture3("gem yank jirametrics -v #{version} --otp #{otp}")
    end

    if status.success?
      puts 'done.'
    else
      puts "WARNING: could not yank #{version} — #{stdout.strip}. Skipping."
    end

    otp
  end

  def create_github_release otp # rubocop:disable Lint/UnusedMethodArgument
    tag = "v#{current_version}"
    puts "Creating GitHub release #{tag}..."
    Tempfile.create(['release-notes', '.md']) do |f|
      f.write release_notes
      f.flush
      system("gh release create #{tag} --title #{tag} --notes-file #{f.path}") ||
        raise('gh release create failed')
    end
  end

  def gemspec_version_string
    content = File.read(@gemspec_path)
    raise "Could not parse version from #{@gemspec_path}" unless content =~ /spec\.version\s*=\s*['"]([^'"]*)['"]/

    $1
  end

  def latest_released_version
    print 'Fetching versions from RubyGems... '
    result = rubygems_versions.map { |v| v[:version] }.max
    puts "latest is #{result || 'none'}"
    result
  end

  def calculate_prerelease_version
    released = latest_released_version
    gemspec_v = current_version
    gemspec_str = gemspec_version_string

    if released.nil? || gemspec_v != released
      gemspec_str
    elsif gemspec_v.prerelease?
      increment_prerelease(gemspec_str)
    else
      increment_stable_to_prerelease(gemspec_str)
    end
  end

  def increment_prerelease version_str
    raise "Cannot parse prerelease version: #{version_str}" unless version_str =~ /^(.*?)pre(\d+)$/

    "#{$1}pre#{$2.to_i + 1}"
  end

  def increment_stable_to_prerelease version_str
    parts = version_str.split('.')
    if parts.length < 3
      parts << '1'
    else
      parts[2] = (parts[2].to_i + 1).to_s
    end
    "#{parts[0..2].join('.')}pre1"
  end

  def update_gemspec_version new_version
    content = File.read(@gemspec_path)
    updated = content.sub(/(spec\.version\s*=\s*['"])[^'"]*(['"])/, "\\1#{new_version}\\2")
    raise "Could not find version line in #{@gemspec_path}" if content == updated

    File.write(@gemspec_path, updated)
    @current_version = nil
  end

  def commit_and_push_version new_version
    puts "Committing version bump to #{new_version}..."
    system("git add #{@gemspec_path}") || raise('git add failed')
    system("git commit -m 'Bump version to #{new_version}'") || raise('git commit failed')
    puts 'Pushing to remote...'
    system('git push') || raise('git push failed')
  end
end
