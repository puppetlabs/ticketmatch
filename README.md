# ticketmatch
Simple utility script for Jira &lt;-> git reconciliation

This script can be used to reconcile the git commit messages and what is contained in Jira. It does
the following:

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
## Command line options/running in CI

If you like, you can specify all needed options via the command line. Usage is shown below; if you
specify continuous integration mode (`--ci`), then all other arguments are required and will abort
if not specified.

```
Usage: ruby ticketmatch.rb [options]
    -f, --from from_rev              from git revision
    -t, --to to_rev                  to git revision
    -p, --project JIRA_project       JIRA project ID
    -v, --version version_fixed_in   JIRA "fixed-in" version (in quotes for now, please)
    -c, --ci                         continuous integration mode (no prompting)
    -h, --help                       this message
```

# Batch processing

If you need to check all the components that comprise `puppet-agent` for a release, use
`pa_matchbatch.sh`. It requires one argument: the revision (SHA or reference) of `puppet-agent` you
care about. It will process `puppet-agent` and all its components that are tagged with a SHA.

Component directories will be cloned from the path provided in their `component.json` file and the
appropriate branch set. If a given component already exists, a Git fetch will be performed to get
things up to date (see environment variables, below, for additional options).

## How to run pa_matchbatch (one way)

set your working directory to someplace (cannot be `puppet-agent`; can be its parent or empty)

```cd <a_directory>```

invoke pa_matchbatch

```path/pa_matchbatch.sh <the_revision>```

## How to run pa_matchbatch (another way)

point the WORKSPACE environment variable to a directory (ditto)

```export WORKSPACE="fully_qualified_path_to_a_dir"```

invoke pa_matchbatch

```path/pa_matchbatch.sh <the_revision>```

## Other environment variables of interest

There are a few additional environment variables (see `WORKSPACE`, above) that control behavior. All
variables have sensible defaults.

`REPO` controls which Git repo to fetch the baseline puppet-agent from. It defaults to
`puppet-agent`.

`TICKETMATCH_PATH` indicates where to find the `ticketmatch.rb` script. It defaults to the same
directory as the `pa_matchbatch.sh` script.

`FETCH_REMOTE` indicates what should be used as the base for a fetch. It defaults to `origin`.

`OVERRIDE_PATH` indicates where to find version overrides. See next section. It defaults to
`/tmp/version_overrides.txt`.

`IGNORE_FOR` contains a (space-separated) list of repos that we do not want to process, i.e.
run ticketmatch on. Each repo should be specified by their foss name (e.g. "puppet-agent" instead
of "puppet-agent-private") since the script internally figures out whether to clone a foss or private
fork. For example, IGNORE_FOR="puppet-agent facter pxp-agent" will not run ticketmatch on puppet-agent,
facter and pxp-agent. It defaults to empty.

`ONLY_ON` contains a (space-separated) list of foss repos that we exclusively want to process, ignoring 
all other repos. For example, ONLY_ON="puppet-agent facter" will run ticketmatch only on puppet-agent and
facter. It defaults to processing all of the repos. Note that if a repo is in both ONLY_ON and IGNORE_REPOS,
then pa_matchbatch.sh will not process it.

## Overriding the JIRA 'fixed in' version

In certain rare circumstances, typically merge-ups, it's possible for an earlier version number to
be chronologically later than a later version number. This results in the wrong version being
picked up as the JIRA 'fixed in' version of interest. It is possible to override this automatic
version selection on a component-by-component basis. Do the following:

create the override file

```touch /tmp/version_overrides.txt```

for each component that needs an override, put in a line that specifies the component and desired
version override

```facter:1.2.3```

There can be as many unique components lines as you like. The presence or absence of the file
controls if things are overridden or not.

# How to read the output

## The git commit section

The output contains some basic sections which roll up git commits that are not associated with a
Jira ticket listed in the git commit.

```
** DOCS
** MAINT
** PACKAGING
** UNMARKED
```

A special section exists for commits that ticketmatch.rb has determined are a  revert, but it could
not associate the revert commit to a specific git commit (based on the revert's description string)

```
** REVERT
    7f663f732  Revert "Merge pull request #5738 from Iristyle/ticket/LTS-1.7/PUP-1980-fix-URI-escaping-for-UTF8"
    7dede9921  Revert "Merge pull request #5964 from Iristyle/ticket/stable/PUP-1890-fix-duplicated-forge-query-parameter-encoding"
```

## Jira ticket numbers

The output also contains Jira ticket names found from the the git commit messages and the Jira
tickets tagged with the fixed version supplied:

Tickets that are preceded by a `--` have an associated Jira ticket with the supplied fixed version.

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

There are 3 sections which try to convey which of the Jira tickets are not in the proper state. Each
section will print a state for the section.

```
----- Git commits in Jira -----
----- Unresolved Jira tickets not in git commits -----
----- Unresolved Jira tickets found in git commits -----
```
