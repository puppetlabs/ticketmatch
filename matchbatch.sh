#!/usr/bin/env bash
set -e

# get rev hashes in the form [comp]:[to_rev]
getComponentRevMap() {
	for componentName in $(for componentFile in $(grep -lv refs/tags configs/components/*.json); do grep -l puppetlabs ${componentFile}; done); do 
		echo -n " $(basename ${componentName} .json):"
		ruby -rjson -e'j = JSON.parse(STDIN.read); print j["ref"]' < ${componentName}
	done
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
		*) (>&2 echo "Error: need to add JIRA fixed-in version mapping for '${1}'.")
			exit 1
		;;
	esac
}

decolorize() {
#	declare input=${1:-$(</dev/stdin)}
	read input
	echo $input | sed -E "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g"
}

# main
[ -z "${1}" ] && { echo "Error: must specify puppet-agent revision to start from."; exit 1; }
[ $(basename ${PWD}) == 'puppet-agent' ] || { echo "Error: must be in puppet-agent directory"; exit 1; }

# need the puppet agent revision as seed
git checkout ${1}

componentRevMap=$(getComponentRevMap)
[ -z "${componentRevMap}" ] && { echo "Note: no components with SHAs found."; }

cd ..

# add puppet-agent to the list of things to check
componentRevMap="puppet-agent:${1} ${componentRevMap}"

for currentPair in ${componentRevMap}; do
	component=$(echo -n ${currentPair} | cut -d: -f1)
	to_rev=$(echo -n ${currentPair} | cut -d: -f2)

	[ -d "${component}" ] || { echo "Error: no directory named '${component}' in ${PWD}."; exit 1; }
	cd ${component}
	git checkout --quiet ${to_rev}

	# get current version [from_rev]
	from_rev=$(git describe --abbrev=0 --tags)

	# get fixed in version; TODO: more robust version match? [fix_ver]
	fix_ver=$(git log -1 --no-merges --oneline -E --grep='\(packaging\) .* version' | sed -e "s/.*'\(.*\)'.*/\1/")

	jiraProjectId=$(getJiraProjectIdFor "${component}")
	jiraFixedInProject=$(getJiraFixedInFor "${component}")
	echo
	echo "Component: ${component}"
	echo "<><><><><><><><><><>"
	ruby ../ticketmatch/ticketmatch.rb --ci -f "${from_rev}" -t "${to_rev}" -p "${jiraProjectId}" -v "${jiraFixedInProject} ${fix_ver}" 2> /dev/null
	echo "<><><><><><><><><><>"
	cd ..
done