#!/bin/bash
#  based on the original script from https://n0where.net/iptables-blacklist-script/
#  additional lists from simestd
#  refactoring by ak_hepcat
PROG="${0##*/}"
PDIR="$(dirname `readlink -f "$0"`)"
DO_RETURN=${SHLVL}
#DEBUG=1

IP4_BLACKLIST_GEN=/etc/ip-blacklist.conf
IP4_BLACKLIST_CUSTOM=/etc/ip-blacklist-custom.conf # optional

BL_SET=blacklist	# name of your ipset hash, in case of multiples

### Blacklists - remember, maximum number of sorted entries is 65,535 (2^16)
WIZLISTS="chinese nigerian russian lacnic exploited-servers" #wizcraft lists
BLACKLISTS=(
"https://reputation.alienvault.com/reputation.snort.gz"
"http://list.iblocklist.com/?list=dgxtneitpuvgqqcpfulq&fileformat=p2p&archiveformat=gz"
"http://list.iblocklist.com/?list=llvtlsjyoyiczbkjsxpf&fileformat=p2p&archiveformat=gz"
"https://rules.emergingthreats.net/blockrules/compromised-ips.txt"
"https://rules.emergingthreats.net/fwrules/emerging-Block-IPs.txt"
"https://sslbl.abuse.ch/blacklist/sslipblacklist_aggressive.csv"
"http://www.us.openbl.org/lists/base_90days.txt"
"https://malc0de.com/bl/IP_Blacklist.txt"
"http://www.projecthoneypot.org/list_of_ips.php?t=d&rss=1" # Project Honey Pot Directory of Dictionary Attacker IPs
"http://check.torproject.org/cgi-bin/TorBulkExitList.py?ip=1.1.1.1"  # TOR Exit Nodes
"http://www.maxmind.com/en/anonymous_proxies" # MaxMind GeoIP Anonymous Proxies
"http://danger.rulez.sk/projects/bruteforceblocker/blist.php" # BruteForceBlocker IP List
"http://rules.emergingthreats.net/blockrules/rbn-ips.txt" # Emerging Threats - Russian Business Networks List
"http://www.spamhaus.org/drop/drop.lasso" # Spamhaus Don't Route Or Peer List (DROP)
"http://cinsscore.com/list/ci-badguys.txt" # C.I. Army Malicious IP List
"http://www.openbl.org/lists/base.txt"  # OpenBL.org 30 day List
"http://www.autoshun.org/files/shunlist.csv" # Autoshun Shun List
"http://lists.blocklist.de/lists/all.txt" # blocklist.de attackers
)

###

trap do_exit SIGINT SIGTERM SIGKILL SIGQUIT SIGABRT SIGSTOP SIGSEGV

do_exit()
{
        STATUS=${1:-0}
        REASON=${2}

	if [ -z "${DEBUG}" ]
	then
		[[ -e "${IP4_BLACKLIST_T}" ]] && rm -f "${IP4_BLACKLIST_T}"
	else
		echo "leaving temp file ${IP4_BLACKLIST_T}"
	fi


        [[ -n "${REASON}" ]] && echo "${REASON}"

        [[ ${DO_RETURN} -eq 1 ]] && return $STATUS || exit $STATUS
}

prerequisites() {

	if [ "$(id | cut -c1-5)" != "uid=0" ] ; then
	  echo "You must be the root user to run ${PROG}"
	  do_exit 1
	fi

	if [ -z "$(which ipset)" ]; then
	  echo "ipset required but not found.  Please install before continuing"
	  do_exit 1
	fi
	
	if [ -z "$(ipset list -n)" ]; then
	  ipset create ${BL_SET} hash:net
	fi

	if [ "${OPT}" != "sets" ]; then
		_iptok=$(iptables -L -n | grep -iE "match-set.*${BL_SET}" )
		if [ -z "${_iptok}" ]; then
		  echo "ipset rule not found in current iptables for blacklist: ${BL_SET}"
		  echo "insert the following rule where appropriate before running this script"
		  echo "    -A INPUT -m set --match-set ${BL_SET} src -j DROP"
		  do_exit 1
		fi
	fi
}

#############################

OPT=${1}

prerequisites

if [ "${OPT}" = "sets" -o "${OPT}" = "stop" ]
then
	do_exit 0
fi

if [ -z "${DEBUG}" ];
then
	SILENT="--silent"
fi

test -e ${IP4_BLACKLIST_GEN} && MLAST=$(stat --format="%Y" ${IP4_BLACKLIST_GEN})
NOW=$(date "+%s")
if [ $((MLAST + 79440)) -lt ${NOW} ]
then
    echo "blacklist cache is older than 24h. Rebuilding, please wait."


	IP4_BLACKLIST_T=$(mktemp /tmp/ip4_bl-XXXXXX.tmp)

	for list in ${BLACKLISTS[@]}
	do
		echo "# ${list}"
		curl ${SILENT} "${list}" | zgrep -Po '(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?'
	done >> ${IP4_BLACKLIST_T}
	
	for list in ${WIZLISTS}; do
		echo "# ${list}"
	        curl ${SILENT} "http://www.wizcrafts.net/${list}-iptables-blocklist.html" | grep -v \< | grep -v \: | grep -v \; | grep -v \# | grep [0-9]
	done >> ${IP4_BLACKLIST_T}
	
	egrep -v "^(#|$)" ${IP4_BLACKLIST_T} ${IP4_BLACKLIST_CUSTOM} 2>/dev/null | sort -n | uniq | ${PDIR}/ipmerge.pl > ${IP4_BLACKLIST_GEN}
	
	LINES=$(wc -l ${IP4_BLACKLIST_GEN} | awk '{print $1}')
	if [ ${LINES} -gt 65535 ]; then
		do_exit 1 "Exceeded max IP entries for ipset"
	fi
else
	echo "building blacklist from existing cache"
fi

ipset flush ${BL_SET}
egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?' ${IP4_BLACKLIST_GEN} | while IFS= read -r IP
do
        ipset add ${BL_SET} ${IP}
done

do_exit
