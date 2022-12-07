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
    -m, --team JIRA_team             JIRA team assigned tickets within JIRA project
    -c, --ci                         continuous integration mode (no prompting)
    -a, --jira-auth-token            personal access token for JIRA authentication
    -h, --help                       this message
```

# Batch processing for puppet-agent and its components


The `pa_matchbatch.sh` script clones a revision of puppet-agent and all of its components, then runs
ticketmatch on everything; This is intended for use during puppet-agent releases. NOTE: the script might not work as inteded on OSX due to the
fact that sed on OSX is different than sed on linux.

### How to run pa_matchbatch

*`pa_matchbatch.sh` requires one argument,* A puppet-agent git reference (a branch name, a SHA, or
a tag). For example, to run ticketmatch on puppet-agent's master branch and all of its components:

```sh
./pa_matchbatch.sh <branch-name>
```

*`pa_matchbatch.sh` clones puppet-agent and its components to the current working directory by default.*
You can override the target directory by setting the `$WORKSPACE` environment variable to some other
directory. You can run `pa_matchbatch.sh` any number of times on the same workspace; The repos will
be fetched each time to check for new updates.

*`pa_matchbatch.sh` assumes that only the Z versions of puppet-agent and its components will change
during a release.* You will need to override this assumption for:

- Any update to an X or Y version number, or
- Any circumstance where the reported version number is incorrect for some reason (a bad mergeup, for example)

To override the assumed version numbers for some or all components, create a text file with one
`<component-name>:<version>` entry on each line. For example, this would override the assumed
versions of puppet, puppet-agent, facter, the resource API, and pxp-agent:

```
puppet:6.3.0
puppet-agent:6.3.0
facter:3.13.0
puppet-resource_api:3.0.0
pxp-agent:1.11.0
```

Specify the path to this file in **`$OVERRIDE_PATH`** while running pa_matchbatch.sh.

If the version numbers for the components are not being overriden even after creating a text file with their versions and defining the **`$OVERRIDE_PATH`** environment variable, check if the puppet-agent and component repos in your ticketmatch repo were cloned during a previous run of `pa_matchbatch.sh`. If so, use this command so they can be re-cloned:

```$  git clean -xffd  ```

### Other environment variables of interest

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

`JIRA_ACCESS_TOKEN` Private tickets can make ticketmatch erroneously report git commits do not have a
matching JIRA ticket. This can be resolved by supplying a JIRA personal access token for this environment
variable, which can be generated by users with sufficient privilege from JIRA.

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

There are 4 sections that try to convey which of the Jira tickets are not in the proper state. Each
section will print a state for the section.

```
----- Git commits in Jira -----
----- Unresolved Jira tickets not in git commits -----
----- Unresolved Jira tickets found in git commits -----
----- Tickets missing release notes -----
```
