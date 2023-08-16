#!/usr/bin/env bash
# vi: set noexpandtab:
set -e
unset CDPATH

# See README.md for arguments and available environment variables.

# where to find the agent
REPO=${REPO:-puppet-agent}
puppet_agent_repo="git@github.com:puppetlabs/${REPO}.git"
PUPPET_AGENT_URL=${PUPPET_AGENT_URL:-${puppet_agent_repo}}
PUPPET_AGENT_DIR=${PUPPET_AGENT_DIR:-${REPO}}

# where to find the ticketmatch.rb script
TICKETMATCH_PATH=${TICKETMATCH_PATH:-$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )}

# where origin actually is
FETCH_REMOTE=${FETCH_REMOTE:-origin}

# where version overrides are specified
overridesFile="/tmp/version_overrides.txt"
OVERRIDE_PATH=$(realpath ${OVERRIDE_PATH:-${overridesFile}})

# read in the auth token
AUTH_TOKEN_ARG="-a ${JIRA_AUTH_TOKEN}"

echo_bold () {
    echo "$(tput bold)${1}$(tput sgr0)"
}

print_divider () {
    echo '<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>'
    echo
}

# shorthand
pushd() {
	builtin pushd "$@" > /dev/null
}

popd() {
	builtin popd "$@" > /dev/null
}

# strips the "-private" part from a repo
# name, useful for private forks
stripPrivateSuffix() {
	echo -n ${1} | sed 's/-private$//'
}

# parses the repo name from a given git URL
parseRepoName() {
	basename ${1} .git
}

# checks if an array contains the given element
containsElement() {
	local array="${1}"
	local element="${2}"

	for e in ${array}; do
		if [[ "${e}" == "${element}" ]]; then
			return 0
		fi
	done

	return 1
}

# get rev hashes in the form [to_rev]|[url]
getComponentRevMap() {

	# handle pxp-agent repo separately
	# pxp-agent-vanagon is only used in puppet-agent 7 or greater
	if [[ ! -d pxp-agent-vanagon  ]] && [[ $(sed -ne "s/\([0-9]*\)\.[0-9]*\.[0-9]*/\1/p" ${PUPPET_AGENT_DIR}/VERSION) -ge 7 ]]; 
	then
		local pxp_agent_version=$(ruby -rjson -e'j = JSON.parse(STDIN.read); printf(j["version"])' < ${PUPPET_AGENT_DIR}/configs/components/pxp-agent.json)
		git clone --quiet git@github.com:puppetlabs/pxp-agent-vanagon.git
		pushd pxp-agent-vanagon
			git fetch --all --quiet
			git checkout --quiet ${pxp_agent_version}
			for componentName in $(for componentFile in $(grep -lv refs/tags configs/components/*.json); do grep -l puppetlabs/ ${componentFile}; done); do
				ruby -rjson -e'j = JSON.parse(STDIN.read); printf(" %s|%s", j["ref"], j["url"])' < ${componentName}
			done
		popd
	fi

	pushd ${PUPPET_AGENT_DIR}
		# looking for components not pinned to a 'refs/tags' element, and of those, filtering out (keeping) the ones owned by puppetlabs
		for componentName in $(for componentFile in $(grep -lv refs/tags configs/components/*.json); do grep -l puppetlabs/ ${componentFile}; done); do
			ruby -rjson -e'j = JSON.parse(STDIN.read); printf(" %s|%s", j["ref"], j["url"])' < ${componentName}
		done
	popd
}

# Find the fixVersion for a project in this release
#
# - If an overrides file was supplied, use the version number from that file
# - Otherwise look for common version files
# - Otherwise try to find the most recent version update in the git log
getFixVerFor() {
	# If an overrides file was supplied, look at it for a version number first
	if [[ -f ${OVERRIDE_PATH} ]]; then
		override=$(grep "${1}:"  ${OVERRIDE_PATH} | cut -d: -f2)
		if [[ -n ${override} ]]; then
			echo ${override}
			return
		fi
	fi

	# puppet-agent has a ./VERSION file that contains only the version number
	if [[ -f VERSION ]]; then
		version=$(echo $(cat VERSION | sed -e 's/\s+//'))
		if [[ -n ${version} ]]; then
			echo ${version}
			return
		fi
	fi

	# Ruby components have a version.rb in various places
	componentName="$(basename ${PWD})"
	if [[ $componentName = "puppet-resource_api" ]]; then
		# The resource api has a './lib/puppet/resource_api/version.rb' which contains a `VERSION = <version>` line
		versionFile="./lib/puppet/resource_api/version.rb"
	else
		# puppet has a './lib/puppet/version.rb' which contains a `PUPPETVERSION = <version>` line
		# hiera has a './lib/hiera/version.rb' which contains a `VERSION = <version>` line
		versionFile="./lib/${componentName}/version.rb"
	fi
	if [[ -f ${versionFile} ]]; then
		version=$(cat ${versionFile} | sed -nE "s/.*VERSION\s*=\s*(\"|')(.+)(\"|').*/\2/p")
		if [[ -n ${version} ]]; then
			echo ${version}
			return
		fi
	fi

	# C++ components have a version in CMakeLists.txt with a line like `project(pxp-agent VERSION <version>)`
	if [[ -f CMakeLists.txt ]]; then
		version=$(cat CMakeLists.txt | sed -nE "s/project\(.*VERSION\s*(.+)\)/\1/p")
		if [[ -n ${version} ]]; then
			echo ${version}
			return
		fi
	fi

	# Otherwise, attempt to find a version update in the git log for the component
	git log -1 --no-merges --oneline -E --grep='\(packaging\) Bump to version .*' | sed -Ee "s/^.*version '?(([0-9]+\.)*[0-9]+).*/\1/"
}

getJiraProjectIdFor() {
	case "${1}" in
		facter) echo FACT
		;;
		facter-ng) echo FACT
		;;
		hiera) echo HI
		;;
		leatherman) echo LTH
		;;
		puppet) echo PUP
		;;
		pxp-agent) echo PCP
		;;
		puppet-agent) echo PA
		;;
		cpp-pcp-client) echo PCP
		;;
		libwhereami) echo FACT
		;;
		marionette-collective) echo MCO
		;;
		puppet-resource_api) echo PDK
		;;
		cpp-hocon) echo HC
		;;
		nssm) echo PA  # this is on purpose
		;;
		puppet-runtime) echo PA
		;;
		*) (>&2 echo "Error: need to add JIRA project mapping for '${1}'.")
			exit 1
		;;
	esac
}

getJiraFixedInFor() {
	case "${1}" in
		facter) echo FACT
		;;
		facter-ng) echo FACT
		;;
		hiera) echo HI
		;;
		leatherman) echo LTH
		;;
		puppet) echo PUP
		;;
		pxp-agent) echo pxp-agent
		;;
		puppet-agent) echo puppet-agent
		;;
		cpp-pcp-client) echo cpp-pcp-client
		;;
		libwhereami) echo whereami  # potential headache
		;;
		marionette-collective) echo MCO
		;;
		puppet-resource_api) echo RSAPI
		;;
		cpp-hocon) echo HC
		;;
		puppet-runtime) echo puppet-agent
		;;
		nssm) echo puppet-agent  # this is on purpose
		;;
		*) (>&2 echo "Error: need to add JIRA fixed-in version mapping for '${1}'.")
			exit 1
		;;
	esac
}

cloneOrFetch() {
	local targetRev=${1}
	local url=${2}

	local repoName=$(parseRepoName ${url})

	if [[ -d ${repoName} ]]; then
		pushd ${repoName}
			echo "Fetching ${FETCH_REMOTE} for ${repoName} rev ${targetRev}..."
			git fetch ${FETCH_REMOTE} --tags --quiet
			git checkout --quiet ${targetRev}
		popd
	else
		echo "Cloning ${repoName}..."
		echo
		git clone --quiet ${url}
		pushd ${repoName}
			git checkout --quiet ${targetRev}
		popd
	fi
}

readRuntimeVersion() {
    echo `grep -Eo '"version":.*?[^\\]"' configs/components/puppet-runtime.json | awk -F ':' '{print $2}'` | tr -d '"'
}

# get puppet-runtime version from the last release
getOldRuntimeRev() {
    latest_tag=$(git describe --abbrev=0 --tags)
    git checkout --quiet ${latest_tag}
    echo $(readRuntimeVersion)
    git checkout --quiet -
}

getAgentVersion() {
    if [[ -f VERSION ]]; then
        version=$(echo $(cat VERSION | sed -e 's/\s+//'))
        if [[ -n ${version} ]]; then
            echo ${version}
        fi
    fi
}

# main
puppetAgentBaseRev=${1}
[[ -z ${puppetAgentBaseRev} ]] && { echo "Error: must specify the puppet-agent revision to start from."; exit 1; }

baseDir=${WORKSPACE:-${PWD}}
[[ -d ${baseDir} ]] || { echo "Error: '${baseDir}' -- no such directory."; exit 1; }
cd ${baseDir}

# get desired revision of puppet-agent in place
cloneOrFetch "${puppetAgentBaseRev}" "${PUPPET_AGENT_URL}"

agent_repo=$(parseRepoName ${PUPPET_AGENT_URL})
pushd ${agent_repo}
    agentVersion=$(getAgentVersion)
    oldRuntimeVersion=$(getOldRuntimeRev)
    newRuntimeVersion=$(readRuntimeVersion)
popd

repoRevMap=$(getComponentRevMap)

echo "starting with repoRevMap '${repoRevMap}'"

[[ -z ${repoRevMap} ]] && { echo "Note: no repos with SHAs found."; }

# add puppet-agent to the list of repos to check
repoRevMap="${puppetAgentBaseRev}|${PUPPET_AGENT_URL} ${repoRevMap}"

# add puppet-runtime to the list
repoRevMap="$newRuntimeVersion|git@github.com:puppetlabs/puppet-runtime.git ${repoRevMap}"

versionsUsed=""
ignored_repos="${IGNORE_FOR}"
only_on="${ONLY_ON}"

echo "operating on repoRevMap '${repoRevMap}'"

for currentItem in ${repoRevMap}; do
	to_rev=$(echo -n ${currentItem} | cut -d'|' -f1)
	repo_url=$(echo -n ${currentItem} | cut -d'|' -f2)
	repo=$(parseRepoName ${repo_url})
	public_name=$(stripPrivateSuffix ${repo})

	# If a non-empty value for ONLY_ON was passed in, then we want to run
	# ticketmatch only on those repos. This is equivalent to ignoring all
	# repos that aren't a part of ONLY_ON.
	if [[ ! -z "${only_on}" ]] && ! containsElement "${only_on}" "${public_name}"; then
		ignored_repos="${ignored_repos} ${public_name}"
	fi

	# something like
	#    [[ "${ignored_repos}" =~ ${public_name} ]]
	# will not work when $ignored_repos contains e.g. puppet-agent
	# and $public_name is puppet.
	if containsElement "${ignored_repos}" "${public_name}"; then
		continue
	fi

	print_divider

	cloneOrFetch "${to_rev}" "${repo_url}"

	pushd ${repo}
		# get current version [from_rev]
		from_rev=$(git describe --abbrev=0 --tags) # | sed -e 's/^v//')
		fix_ver=$(getFixVerFor "${public_name}")
		jiraProjectId=$(getJiraProjectIdFor "${public_name}")
		jiraFixedInProject=$(getJiraFixedInFor "${public_name}")

        	if [[ $public_name = "puppet-runtime" ]]; then
           		from_rev=${oldRuntimeVersion}
           		fix_ver=${agentVersion}
           		versionsUsed="${versionsUsed}\n${public_name}:${to_rev}"
        	else
           		versionsUsed="${versionsUsed}\n${public_name}:${fix_ver}"
        	fi

		echo_bold "Ticketmatch results for $public_name"
		echo "(From tag '$from_rev' to ref '$to_rev' - JIRA fixVersion is '$(getJiraFixedInFor $public_name) $fix_ver')"
		echo
		ruby ${TICKETMATCH_PATH}/ticketmatch.rb --ci -f "${from_rev}" -t "${to_rev}" -p "${jiraProjectId}" -v "${jiraFixedInProject} ${fix_ver}" ${AUTH_TOKEN_ARG}| sed 's/^/\t/g'
		echo
	popd
done

print_divider

echo "The following versions were used for JIRA searches (repo_name:version)"
echo_bold "If these versions are incorrect, you should create a version overrides file and try again. See the README."
printf "%b\n\n" ${versionsUsed}
