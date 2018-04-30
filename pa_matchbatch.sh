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
	local repoName=${1}
	local targetRev=${2}
	local url=${3}

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
cloneOrFetch "puppet-agent" "${puppetAgentBaseRev}" "${PUPPET_AGENT_URL}"

repoRevMap=$(getComponentRevMap)
[[ -z ${repoRevMap} ]] && { echo "Note: no repos with SHAs found."; }
# add puppet-agent to the list of repos to check
repoRevMap="${puppetAgentBaseRev}|${PUPPET_AGENT_URL} ${repoRevMap}"

versionsUsed=""

for currentItem in ${repoRevMap}; do
	to_rev=$(echo -n ${currentItem} | cut -d'|' -f1)
	repo_url=$(echo -n ${currentItem} | cut -d'|' -f2)
	repo=$(basename ${repo_url} .git)

	echo "<><><><><><><><><><>"
	cloneOrFetch "${repo}" "${to_rev}" "${repo_url}"
	pushd ${repo}

	  # get current version [from_rev]
	  from_rev=$(git describe --abbrev=0 --tags) # | sed -e 's/^v//')
	  fix_ver=$(getFixVerFor "${repo}")
	  jiraProjectId=$(getJiraProjectIdFor "${repo}")
	  jiraFixedInProject=$(getJiraFixedInFor "${repo}")

	  versionsUsed="${versionsUsed}\n${repo}:${fix_ver}"

	  echo "Checking: ${repo}"
	  echo "from_rev: $from_rev, to_rev: $to_rev, fix_ver: $fix_ver"
	  ruby ${TICKETMATCH_PATH}/ticketmatch.rb --ci -f "${from_rev}" -t "${to_rev}" -p "${jiraProjectId}" -v "${jiraFixedInProject} ${fix_ver}" 2> /dev/null
	  echo
	popd
done

echo "<><><><><><><><><><>"
echo "Versions used for JIRA searches (repo:version)"
printf "%b\n" ${versionsUsed}
