# This script mangles the output from git log between two git references
# and matches this with a list of tickets from Jira that corresponds to
# a project and a fixVersion
#
# You must cd to the puppet get repo for this to work.
#
require 'rubygems'
require 'highline/import' # see https://github.com/JEG2/highline
require 'json'

git_from = ask('Enter Git From Rev: ')
git_to = ask('Enter Git To Rev: ') { |q| q.default = 'master' }

# Get the log from git
# process and store in a hash per user entered ticket reference
#
result = Hash.new {|h, k| h[k] = [] }
a = %x{git log --no-merges --oneline #{git_from}..#{git_to}}
a.each_line do |line|
  m = line.match(/^([0-9a-fA-F]+)\s+(?:\(([^\)]*)\))?(.*)$/)
  result[(m[2] || 'unmarked').upcase] << [m[1], m[3]]
end

if result.empty?
  say("No results found in git log for range #{git_from}..#{git_to}")
  exit(status=1)
end

jira_project = ask('Enter JIRA project: ') { |q| q.default = 'PUP' }
jira_version = ask('Enter JIRA fix version: ')
jira_data = {
    :jql => "project = #{jira_project} AND fixVersion = \"#{jira_version}\" ORDER BY key",
    :maxResults => -1,
    :fields => ['status']
}
# Process file with Jira issues
post_data = JSON.fast_generate(jira_data)
begin
  jira_issues = JSON.parse(%x{curl -X POST -H 'Content-Type: application/json' --data '#{post_data}' https://tickets.puppetlabs.com/rest/api/2/search})
rescue
  say('Unable to obtain list of issues from JIRA')
  exit(status=1)
end
# puts JSON.pretty_unparse(jira_issues)

known_issues = (jira_issues['issues'] || []).reduce({}) {|memo, i| memo[i['key']] = [:not_in_git, i['fields']['status']['name']]; memo}
if known_issues.empty?
  say("JIRA returned no results for project '#{jira_project}' and fix version '#{jira_version}'")
  exit(status=1)
end

# Print list of ssues sorted, for each show sha + comment after reference
#
result.keys.sort.each do |k|
  resolution = known_issues[k]
  if resolution.nil?
    puts "** #{k.upcase}"
  else
    puts "-- #{k.upcase} (#{resolution[1]})"
    resolution[0] = :in_git
  end
  v = result[k]
  v.each do | data |
    puts "    #{data[0]}  #{data[1]}"
  end
end
puts "---"
unresolved = known_issues.reject {|k,v| v[1] == 'Resolved' || v[1] == 'Closed' }
unresolved_not_in_git = unresolved.reject {|k,v| v[0] == :in_git}
if !unresolved_not_in_git.empty?
  say("<%= color('UNRESOLVED ISSUES NOT FOUND IN GIT', RED) %>")
  unresolved_not_in_git.each_pair { |k,v| say("<%= color('#{k} #{v[1]}', RED) %>")}
else
  say("<%= color('ALL ISSUES WERE FOUND IN GIT', GREEN) %>")
end

unresolved_in_git =  unresolved.select {|k,v| v[0] == :in_git}
if !unresolved_in_git.empty?
  say("<%= color('UNRESOLVED ISSUES FOUND IN GIT', RED) %>")
  unresolved_in_git.each_pair { |k,v| say("<%= color('#{k} #{v[1]}', RED) %>")}
end
