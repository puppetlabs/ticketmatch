# This script mangles the output from git log between two git references
# and matches this with a list of tickets from Jira that corresponds to
# a project and a fixVersion
#
# You must cd to the git repo for this to work.
#

require 'rubygems'
require 'highline/import' # see https://github.com/JEG2/highline
require 'json'
require 'optparse'

# store the basic information of a git log message
class GitEntry
  attr_reader :hash, :description
  attr_accessor :revert_entry, :has_revert_parent

  def initialize(hash, description)
    @hash        = hash
    @description = description
    # The GitEntry that is a revert of this commit
    @revert_entry = nil
    # we set this in the revert entry so we can avoid printing it twice
    @has_revert_parent = false
  end

  def <=>(another_entry)
    [self.hash, self.description] <=> [another_entry.hash, another_entry.description]
  end
end

# hold all the git commit log messages, but group them based on their ticket number or "type"
class GitCommit
  def initialize
    @git_entries = Hash.new
  end

  def add_git_commit_line(line)
    # is this a revert?
    m = line.match(/^([0-9a-fA-F]+)\s+(Revert ".*")$/)
    unless m.nil?
      hash        = m[1]
      description = m[2]
      add_git_entry('REVERT', hash, description)
      return
    end
    m = line.match(/^([0-9a-fA-F]+)\s+(?:\(([^\)]*)\))?(.*)$/)
    if m[2].nil?
      hash        = m[1]
      description = m[3]
      add_git_entry('UNMARKED', hash, description)
    else
      type        = m[2].upcase
      hash        = m[1]
      description = m[3].lstrip
      add_git_entry(type, hash, description)
    end
  end

  def add_git_entry(type, hash, description)
    if @git_entries[type].nil?
      @git_entries[type] = [GitEntry.new(hash, description)]
    else
      @git_entries[type] << GitEntry.new(hash, description)
    end
  end

  def set_has_revert_parent_for_entry(entry)
    @git_entries.each_key do |ticket|
      @git_entries[ticket].length.times do |entry_offset|
        if @git_entries[ticket][entry_offset] == entry
          @git_entries[ticket][entry_offset].has_revert_parent = true
        end
      end
    end
  end

  def find_commit_that_matches_description(description_pattern)
    @git_entries.each_key do |ticket|
      @git_entries[ticket].length.times do |entry_offset|
        if @git_entries[ticket][entry_offset].description =~ description_pattern
          return @git_entries[ticket][entry_offset]
        end
      end
    end
    return nil
  end

  # we have to look 2 ways for reverts to find them all
  # 1 - look using the "(TICKET) <description>"
  # 2 - look using the "Revert "<description>""
  def associate_reverts
    @git_entries.each_key do |ticket|
      @git_entries[ticket].length.times do |entry_offset|
        # look for reverts based on the ticket name and description string
        description_pattern = /^Revert "\(#{ticket}\) #{Regexp.escape(@git_entries[ticket][entry_offset].description)}"$/
        revert              = find_commit_that_matches_description(description_pattern)
        unless revert.nil?
          @git_entries[ticket][entry_offset].revert_entry = revert
          set_has_revert_parent_for_entry(revert)
        end

        # look for reverts based on the Revert string using just the description
        description_pattern = /^Revert "#{Regexp.escape(@git_entries[ticket][entry_offset].description)}"$/
        revert              = find_commit_that_matches_description(description_pattern)
        unless revert.nil?
          @git_entries[ticket][entry_offset].revert_entry = revert
          set_has_revert_parent_for_entry(revert)
        end
      end
    end
  end

  def keys
    @git_entries.keys
  end

  def [](key)
    @git_entries[key]
  end

  def empty?
    @git_entries.empty?
  end

  def inspect
    string = ""
    @git_entries.each_key do |key|
      string += "{#{key}: #{@git_entries[key].inspect} }\n"
    end
    string
  end
end

# the basic state of a jira ticket
#
class JiraState
  attr_accessor :in_git
  attr_reader :state

  def initialize(state, in_git=0)
    @state  = state
    @in_git = in_git # This is a count, if its its non-zero then something was still checked in for this ticket
  end
end

# A grouping of Jira tickets that apply for this matching session
#
class JiraTickets
  def initialize
    @tickets = Hash.new
  end

  def [](ticket)
    @tickets[ticket]
  end

  def keys
    @tickets.keys
  end

  def add_ticket(ticket, state, in_git=0)
    @tickets[ticket] = JiraState.new(state, in_git)
  end

  def empty?
    @tickets.empty?
  end

  def inspect
    string = ""
    @tickets.each_key do |key|
      string += "{#{key}: #{@tickets[key].inspect} }\n"
    end
    string
  end
end

git_from_rev = nil
git_to_rev = nil
jira_project_name = nil
jira_project_fixed_version = nil
interactive = true

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: ruby ticketmatch.rb [options]'

  opts.on('-f', '--from from_rev', 'from git revision') do |from_rev|
    git_from_rev = from_rev;
  end

  opts.on('-t', '--to to_rev', 'to git revision') do |to_rev|
    git_to_rev = to_rev;
  end

  opts.on('-p', '--project JIRA_project', 'JIRA project ID') do |project_name|
    jira_project_name = project_name;
  end

  opts.on('-v', '--version version_fixed_in', 'JIRA "fixed-in" version (in quotes for now, please)') do |fixed_version|
    jira_project_fixed_version = fixed_version;
  end

  opts.on('-c', '--ci', 'continuous integration mode (no prompting)') do
    interactive = false;
  end

  opts.on('-h', '--help', 'this message') do
    puts opts
    exit 1
  end
end

parser.parse!

# check if we are in a git tree or not
#
in_repo = %x{git rev-parse --is-inside-work-tree 2>/dev/null}
unless in_repo.chomp == "true"
  say('ERROR: Please run ticketmatch from a git repo directory')
  exit 1
end

if git_from_rev == nil
  if interactive
    git_from_rev = ask('Enter Git From Rev: ')
  else
    abort('ERROR: must specify a Git from revision')
  end
end

if git_to_rev == nil
  if interactive
    git_to_rev = ask('Enter Git To Rev: ') {|q| q.default = 'master'}
  else
    abort('ERROR: must specify a Git to revision')
  end
end

# Get the log from git
# process and store in a hash per user entered ticket reference
#
git_commits = GitCommit.new
git_log     = %x{git log --no-merges --oneline #{git_from_rev}..#{git_to_rev}}
git_log.each_line do |line|
  git_commits.add_git_commit_line(line)
end
if git_commits.empty?
  say("No results found in git log for range #{git_from_rev}..#{git_to_rev}")
  exit 0
end

# associate the reverts
#
git_commits.associate_reverts

# collect the Jira information
#
if jira_project_name == nil
  if interactive
    jira_project_name = ask('Enter JIRA project: ') {|q| q.default = 'PUP'}
  else
    abort('ERROR: must specify a JIRA project ID')
  end
end

if jira_project_fixed_version == nil
  if interactive
    jira_project_fixed_version = ask('Enter JIRA fix version: ') do |q|
      q.default = "#{jira_project_name} #{git_to_rev}"
    end
  else
    abort('ERROR: must specify a JIRA fix version')
  end
end

# get the list of tickets from the JIRA project that contain the fixed version
jira_data = {
    :jql        => "project = #{jira_project_name} AND fixVersion = \"#{jira_project_fixed_version}\" ORDER BY key",
    :maxResults => -1,
    :fields     => ['status']
}
# Process file with Jira issues
jira_post_data = JSON.fast_generate(jira_data)
begin
  jira_issues = JSON.parse(%x{curl -X POST -H 'Content-Type: application/json' --data '#{jira_post_data}' https://tickets.puppetlabs.com/rest/api/2/search})
rescue
  say('Unable to obtain list of issues from JIRA')
  exit(status=1)
end
# puts JSON.pretty_unparse(jira_issues)

if jira_issues['issues'].nil?
  say("JIRA returned no results for project '#{jira_project_name}' and fix version '#{jira_project_fixed_version}'")
  exit 0
end
jira_tickets = JiraTickets.new
jira_issues['issues'].each do |issue|
  jira_tickets.add_ticket(issue['key'], issue['fields']['status']['name'], in_git=0)
end
if jira_tickets.empty?
  say("JIRA returned no results for project '#{jira_project_name}' and fix version '#{jira_project_fixed_version}'")
  exit 0
end

# Print list of issues sorted, for each show sha + comment after reference
#
git_commits.keys.sort.each do |ticket|
  if jira_tickets[ticket].nil?
    puts "** #{ticket.upcase}"
  else
    puts "-- #{ticket.upcase} (#{jira_tickets[ticket].state})"
  end
  git_commits[ticket].each do |git_entry|
    next if git_entry.has_revert_parent # skip this entry if its a revert with a parent, (the parent will print it)

    # list this entry and any of its
    puts "    #{git_entry.hash}  #{git_entry.description}"
    revert_ticket = git_entry.revert_entry
    until revert_ticket.nil?
      puts " R  #{revert_ticket.hash}  #{revert_ticket.description}"
      revert_ticket = revert_ticket.revert_entry
    end
  end
end

# figure out what is in git or not based on taking reverts into account
# we add +1 for the initial code and then -1, or +1 depending on the level of the revert
# if the number is non-zero then this ticket had a code change
#
git_commits.keys.each do |ticket|
  # if we have not jira ticket for this one move on
  next if jira_tickets[ticket].nil?
  git_commits[ticket].each do |git_entry|
    # if this git_entry has a parent revert_ticket, let that one do the counting
    next if git_entry.has_revert_parent

    # add 1 for this ticket adding code
    jira_tickets[ticket].in_git += 1

    in_git        = -1
    revert_ticket = git_entry.revert_entry
    until revert_ticket.nil?
      # now add either -1 or +1 depending on Revert level
      jira_tickets[ticket].in_git += in_git
      revert_ticket = revert_ticket.revert_entry
      in_git        = -in_git
    end
  end
end

puts
puts '----- Git commits in Jira -----'
known_jira_tickets = jira_tickets.keys
unknown_issues     = git_commits.keys.reject do |ticket|
  known_jira_tickets.include?(ticket) || ["MAINT", "DOC", "DOCS", "TRIVIAL", "PACKAGING", "UNMARKED"].include?(ticket)
end
if !unknown_issues.empty?
  say("<%= color('COMMIT TOKENS NOT FOUND IN JIRA (OR NOT WITH FIX VERSION OF #{jira_project_fixed_version})', RED) %>")
  unknown_issues.sort.each do |ticket|
    if ticket == 'REVERT'
      git_commits[ticket].each do |revert_ticket|
        say("<%= color('REVERT #{revert_ticket.hash}', RED) %>")
      end
    else
      say("<%= color('#{ticket}', RED) %>")
    end
  end
else
  say("<%= color('ALL COMMIT TOKENS WERE FOUND IN JIRA', GREEN) %>")
end

puts
puts '----- Unresolved Jira tickets not in git commits -----'
unresolved            = known_jira_tickets.reject do |ticket|
  jira_tickets[ticket].state == 'Resolved' || jira_tickets[ticket].state == 'Closed'
end
unresolved_not_in_git = unresolved.reject {|ticket| jira_tickets[ticket].in_git >= 1}
if !unresolved_not_in_git.empty?
  say("<%= color('UNRESOLVED ISSUES NOT FOUND IN GIT', RED) %>")
  unresolved_not_in_git.each {|ticket| say("<%= color('#{ticket} #{jira_tickets[ticket].state}', RED) %>")}
else
  say("<%= color('ALL ISSUES WERE FOUND IN GIT', GREEN) %>")
end

puts
puts '----- Unresolved Jira tickets found in git commits -----'
unresolved_in_git = unresolved.select {|ticket| jira_tickets[ticket].in_git >= 1}
if !unresolved_in_git.empty?
  say("<%= color('UNRESOLVED ISSUES FOUND IN GIT', RED) %>")
  unresolved_in_git.each {|ticket| say("<%= color('#{ticket} #{jira_tickets[ticket].state}', RED) %>")}
else
  say("<%= color('ALL ISSUES WERE RESOLVED IN JIRA', GREEN) %>")
end

exit 0
