# ticketmatch
Simple utility script for Jira &lt;-> git reconciliation

This script can be used to reconcile the git commit messages and what
is contained in Jira. It does the following:

* Collects the list of commits between the 2 provided git revisions
* Collects the Jira tickets for a project and the fixed version
* Reconciles the git commit ticket tags with the Jira ticket states
* Associates reverts with the parent commit if possible

# What you need

* A checkout of the git repo to match tickets against
* The revisions to check between
  * These can be tags, hashes, HEAD, etc. (see gitrevisions)
* The Jira project name (example PUP)
* The Jira fix version to look for (example "PUP 4.10.5")

# How to read the output

## The git commit section

The output contains some basic sections which roll up git commits that are not
associated with a Jira ticket listed in the git commit.

```
** DOCS
** MAINT
** PACKAGING
** UNMARKED
```

A special section exists for commits that ticketmatch.rb has determined are a 
revert, but it could not associate the revert commit to a specific git commit
(based on the revert's description string)

```
** REVERT
    7f663f732  Revert "Merge pull request #5738 from Iristyle/ticket/LTS-1.7/PUP-1980-fix-URI-escaping-for-UTF8"
    7dede9921  Revert "Merge pull request #5964 from Iristyle/ticket/stable/PUP-1890-fix-duplicated-forge-query-parameter-encoding"
```

## Jira ticket numbers

The output also contains Jira ticket names found from the the git commit messages
and the Jira tickets tagged with the fixed version supplied:

Tickets that are preceded by a `--` have an associated Jira ticket with the supplied
fixed version.

Tickets that are preceded by a `**` were listed in the git commit messages only

The `R` in column 2 denotes that the git commit is a revert of the preceding commit

```
-- PUP-6660 (Closed)
    268135c91  Remove `--no-use_cached_catalog` flag from `--test` flag
** PUP-6675
    8ba63052a  Use pipes instead of temporary files for Puppet exec
 R  e97179356  Revert "(PUP-6675) Use pipes instead of temporary files for Puppet exec"
    651936006  Use pipes instead of temporary files for Puppet exec
 R  e97179356  Revert "(PUP-6675) Use pipes instead of temporary files for Puppet exec"
    8cec657e2  Add exec test using large output
```

## Jira Ticket status

There are 3 sections which try to convey which of the Jira tickets are not in
the proper state. Each section will print a state for the section.
```
----- Git commits in Jira -----
----- Unresolved Jira tickets not in git commits -----
----- Unresolved Jira tickets found in git commits -----
```

# How to run ticketmatch

```$ cd <git_project_directory>  ```

checkout the branch you want to run against  

```$ git checkout 5.0.x  ```

Run ticketmatch.rb

```
$ ruby path/ticketmatch.rb  
Enter Git From Rev: 4.10.2
Enter Git To Rev: |master| 4.10.3
Enter JIRA project: |PUP|
Enter JIRA fix version: |PUP 4.10.3|
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  2001  100  1897  100   104   7295    399 --:--:-- --:--:-- --:--:--  7324
** MAINT
    e8bc39dba  correct comment in CharacterEncoding::scrub
-- PUP-7650 (Closed)
    a75f3c10a  Remove dead code and unnecessary call to #downcase
    089ae6286  Fix issue related to deserialization of types
    6f0e92737  Ensure that Loader::TypedName always uses lower-case
-- PUP-7666 (Closed)
    3dfa1cdb3  Update puppet version to 4.10.3
** REVERT
    7f663f732  Revert "Merge pull request #5738 from Iristyle/ticket/LTS-1.7/PUP-1980-fix-URI-escaping-for-UTF8"
    7dede9921  Revert "Merge pull request #5964 from Iristyle/ticket/stable/PUP-1890-fix-duplicated-forge-query-parameter-encoding"

----- Git commits in Jira -----
COMMIT TOKENS NOT FOUND IN JIRA (OR NOT WITH FIX VERSION OF PUP 4.10.3)
REVERT 7f663f732
REVERT 7dede9921

----- Unresolved Jira tickets not in git commits -----
ALL ISSUES WERE FOUND IN GIT

----- Unresolved Jira tickets found in git commits -----
ALL ISSUES WERE RESOLVED IN JIRA
```