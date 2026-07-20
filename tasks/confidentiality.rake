# frozen_string_literal: true

# Confidentiality guard for test fixtures.
#
# This is a public, open-source repository. Its specs and fixtures must reference only
# neutral, obviously-fictional identifiers -- placeholders like example-org or
# example.atlassian.net -- and never a real customer's organisation, repository, or Jira
# instance. This task fails the build if a fixture names something outside that set.
#
# We enforce it with an ALLOWLIST, not a denylist, on purpose. A denylist would mean
# maintaining an ever-growing roster of every organisation we must avoid naming -- unbounded
# upkeep, and no protection at all for one we haven't listed yet. An allowlist inverts the
# burden: we name the small, stable set of placeholders we DO permit, and anything else in a
# fixture trips the check automatically, with zero per-organisation maintenance.
#
# The scan is deliberately narrow. It looks at the two identifier shapes most likely to carry
# a real name into a fixture -- GitHub repo URLs (github.com/<org>/<repo>) and Jira hosts
# (<host>.atlassian.net) -- which keeps it high-signal and cheap. It is a fixture-hygiene
# backstop, not a general secrets scanner.

# GitHub orgs permitted in specs: neutral placeholders plus our own account.
ALLOWED_GITHUB_ORGS = %w[example example-org owner acme foo sample mikebowler].freeze

# Jira hosts permitted in specs: neutral placeholders plus our own instance.
ALLOWED_JIRA_HOSTS = %w[example sample improvingflow].freeze

GITHUB_ORG_PATTERN = %r{github\.com[/:]([A-Za-z0-9_.-]+)}
JIRA_HOST_PATTERN = /([A-Za-z0-9_-]+)\.atlassian\.net/

desc 'Fail if any spec references a real (non-placeholder) GitHub org or Jira host'
task :check_confidentiality do
  violations = []

  # Only tracked files under spec/ -- that is where fixtures live, and scanning the git
  # index skips scratch files. Prose elsewhere (docs, the gemspec) may legitimately name
  # real projects and people, so it is intentionally out of scope.
  `git ls-files spec`.split("\n").each do |file|
    File.read(file).scrub.each_line.with_index(1) do |line, number|
      line.scan(GITHUB_ORG_PATTERN).flatten.each do |org|
        next if ALLOWED_GITHUB_ORGS.include?(org.downcase)

        violations << "#{file}:#{number} unlisted GitHub org #{org.inspect}"
      end
      line.scan(JIRA_HOST_PATTERN).flatten.each do |host|
        next if ALLOWED_JIRA_HOSTS.include?(host.downcase)

        violations << "#{file}:#{number} unlisted Jira host #{host.inspect}"
      end
    end
  end

  unless violations.empty?
    warn 'Confidentiality check failed. Specs may reference only placeholder identifiers ' \
      '(e.g. example-org, example.atlassian.net):'
    violations.each { |violation| warn "  #{violation}" }
    # Extend the allowlist above ONLY for a genuine placeholder or one of our own accounts --
    # never to wave through a real customer's name.
    abort "Found #{violations.size} unlisted identifier(s) in specs."
  end
end
