#!/usr/bin/env bash
set -e
unset CDPATH

# where to find the agent
puppet_agent_repo="git@github.com:puppetlabs/puppet-agent.git"
PUPPET_AGENT_URL=${PUPPET_AGENT_URL:-${puppet_agent_repo}}

# where to find the ticketmatch.rb script
TICKETMATCH_PATH=${TICKETMATCH_PATH:-$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )}

# where origin actually is
FETCH_REMOTE=${FETCH_REMOTE:-origin}

# where version overrides are specified
overridesFile="/tmp/version_overrides.txt"
OVERRIDE_PATH=${OVERRIDE_PATH:-${overridesFile}}

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
	pushd puppet-agent
	  # looking for components not pinned to a 'refs/tags' element, and of those, filtering out (keeping) the ones owned by puppetlabs
	  for componentName in $(for componentFile in $(grep -lv refs/tags configs/components/*.json); do grep -l puppetlabs ${componentFile}; done); do
		  ruby -rjson -e'j = JSON.parse(STDIN.read); printf(" %s|%s", j["ref"], j["url"])' < ${componentName}
	  done
	popd
}

# TODO: more robust version matches?
# if version file present, use it, otherwise calculate
# only override versions you care about
# repo:fix_version, 1 per line
#
getFixVerFor() {
	if [[ -f  ${OVERRIDE_PATH} ]]; then
		override=$(grep ${1}  ${OVERRIDE_PATH} | cut -d: -f2)
		[[ -n ${override} ]] && { echo ${override}; return; }
	fi

	case ${1} in
		puppet-resource_api)
			git log -1 --no-merges --oneline --grep='Release prep' | sed -e "s/.*prep for v\(.*$\)/\1/"
		;;
		*)
			git log -1 --no-merges --oneline -E --grep='\(packaging\) Bump to version .*' | sed -Ee "s/^.*version '?(([0-9]+\.)*[0-9]+).*/\1/"
		;;
	esac
}

getJiraProjectIdFor() {
	case "${1}" in
		facter) echo FACT
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
		*) (>&2 echo "Error: need to add JIRA project mapping for '${1}'.")
			exit 1
		;;
	esac
}

getJiraFixedInFor() {
	case "${1}" in
		facter) echo FACT
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
		puppet-resource_api) echo PDK
		;;
		cpp-hocon) echo HC
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
		  echo "Note: fetch ${FETCH_REMOTE} for ${repoName}..."
		  git fetch ${FETCH_REMOTE} --quiet
		  git checkout --quiet ${targetRev}
		popd
	else
		echo "Note: cloning ${repoName}..."
		git clone --quiet ${url}
		pushd ${repoName}
		  git checkout --quiet ${targetRev}
		popd
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

repoRevMap=$(getComponentRevMap)
[[ -z ${repoRevMap} ]] && { echo "Note: no repos with SHAs found."; }
# add puppet-agent to the list of repos to check
repoRevMap="${puppetAgentBaseRev}|${PUPPET_AGENT_URL} ${repoRevMap}"

versionsUsed=""
ignored_repos="${IGNORE_FOR}"
only_on="${ONLY_ON}"

for currentItem in ${repoRevMap}; do
	to_rev=$(echo -n ${currentItem} | cut -d'|' -f1)
	repo_url=$(echo -n ${currentItem} | cut -d'|' -f2)
	repo=$(parseRepoName ${repo_url})
	foss_name=$(stripPrivateSuffix ${repo})

	# If a non-empty value for ONLY_ON was passed-in, then we want to run
	# ticketmatch only on those repos. This is equivalent to ignoring all
	# repos that aren't a part of ONLY_ON.
	if [[ ! -z "${only_on}" ]] && ! containsElement "${only_on}" "${foss_name}"; then
		ignored_repos="${ignored_repos} ${foss_name}"
	fi

	# something like
	#    [[ "${ignored_repos}" =~ ${foss_name} ]]
	# will not work when $ignored_repos contains e.g. puppet-agent
	# and $foss_name is puppet.
	if containsElement "${ignored_repos}" "${foss_name}"; then
		continue
	fi

	echo "<><><><><><><><><><>"
	cloneOrFetch "${to_rev}" "${repo_url}"
	pushd ${repo}

	  # get current version [from_rev]
	  from_rev=$(git describe --abbrev=0 --tags) # | sed -e 's/^v//')
	  fix_ver=$(getFixVerFor "${foss_name}")
	  jiraProjectId=$(getJiraProjectIdFor "${foss_name}")
	  jiraFixedInProject=$(getJiraFixedInFor "${foss_name}")

	  versionsUsed="${versionsUsed}\n${foss_name}:${fix_ver}"

	  echo "Checking: ${foss_name}"
	  echo "from_rev: $from_rev, to_rev: $to_rev, fix_ver: $fix_ver"
	  ruby ${TICKETMATCH_PATH}/ticketmatch.rb --ci -f "${from_rev}" -t "${to_rev}" -p "${jiraProjectId}" -v "${jiraFixedInProject} ${fix_ver}" 2> /dev/null
	  echo
	popd
done

echo "<><><><><><><><><><>"
echo "Versions used for JIRA searches (foss_repo:version)"
printf "%b\n" ${versionsUsed}
