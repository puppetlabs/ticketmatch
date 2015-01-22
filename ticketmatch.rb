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
    :fields => ['key']
}
# Process file with Jira issues
post_data = JSON.fast_generate(jira_data)
begin
  jira_issues = JSON.parse(%x{curl -X POST -H 'Content-Type: application/json' --data '#{post_data}' https://tickets.puppetlabs.com/rest/api/2/search})
rescue
  say('Unable to obtain list of issues from JIRA')
  exit(status=1)
end

known_issues = jira_issues['issues'].reduce({}) {|memo, i| memo[i['key']] = true; memo}

# Print list of ssues sorted, for each show sha + comment after reference
#
result.keys.sort.each do |k|
  if known_issues[k]
    marker = '--'
    known_issues[k] = :in_git
  else
    marker = '**'
  end
  puts "#{marker} #{k.upcase}"
  v = result[k]
  v.each do | data |
    puts "    #{data[0]}  #{data[1]}"
  end
end
puts "---"
not_found = known_issues.select {|k,v| v != :in_git }
if !not_found.empty?
  say("<%= color('ISSUES NOT FOUND IN GIT', RED) %>")
  not_found.keys.each { |k| say("<%= color('#{k}', RED) %>")}
else
  say("<%= color('ALL ISSUES WERE FOUND IN GIT', GREEN) %>")
end
