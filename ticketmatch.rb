# This script mangles the output from git log between two git references
# and matches this with a list of tickets from Jira.
#
# The List from Jira can be obtained by showing the list of issues for a release
# i.e. a query like this for the given release which gets all targeting the
# release in question:
#
#   project = PUP AND fixVersion = "3.5.0" ORDER BY key ASC
#
# Then removing all columns from the output except key.
# (This is done by selecting columns in the menu far right above the list)
# Then exporting it to Excel, and then from Excel to a CSV
# the CVS will be in MS format with \r instead of \n, change that by
# running:
#
#    tr '\r' '\n' < the_file.csv > jiraissues.txt
#
# Then edit the jiraissues.txt to remove the header and footer lines
#
# Then change the from and to in this script to the tags you want to
# compare
#
# You must cd to the puppet get repo for this to work, and place
# the extra files there as well.
#
from = "3.4.3"
to = "master"

# Get the log from git
# process and store in a hash per user entered ticket reference
#
result = Hash.new {|h, k| h[k] = [] }
a = %x{git log --no-merges --oneline #{from}..#{to}}
a.each_line do |line|
  m = line.match(/^([0-9a-fA-F]+)\s+(\([^\)]*\))?(.*)$/)
  result[(m[2] || 'unmarked').upcase] << [m[1], m[3]]
end

# Process file with Jira issues
jiratext = File.read('jiraissues.txt')
known_issues = jiratext.each_line.reduce({}) {|memo, line| memo["(#{line.chomp})"] = true; memo }

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
puts "ISSUES NOT FOUND IN GIT"
puts known_issues.select {|k,v| v != :in_git }.keys.join("\n")
