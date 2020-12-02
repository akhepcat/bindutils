#!/bin/bash
### 
###  Updates the MTA-STS record to match the defined webserver's TLS certificate
###

if [ ! -r "${0}.local" ]
then
	# Global settings
	ext_ns="ns-cache.example.net"		# external NS for testing
	keyfile="/etc/bind/named.keys"		# Where your keys are located

	#####
	# Per-host settings

	NSC=$((NSC + 1))			# (auto-increment)		# every MTA-STS record gets a block
	DOMAIN[$NSC]="example.net"		# local domain name
	AUTH_NS[$NSC]="ext-ns.example.net"	# authoritative nameserver	# Copy this block for each nameserver you have
	RNDC_KEY[$NSC]="external"		# rndc key for this ns		# the script auto-iterates over them

	NSC=$((NSC + 1))			# (auto-increment)		# every MTA-STS record gets a block
	DOMAIN[$NSC]="example.com"		# local domain name
	AUTH_NS[$NSC]="int-ns.example.net"	# authoritative nameserver	# Copy this block for each nameserver you have
	RNDC_KEY[$NSC]="internal"		# rndc key for this ns		# the script auto-iterates over them

else
	# Read in the setting from the .local config
	. "${0}.local"
fi

######

getkey() {
	secret=$(grep -iEw 'key|secret' "${keyfile}" | grep -A1 "${kname}" | grep secret | awk '{print $2}' | cut -f 1 -d\; | tr -d [\'\"]  )
	algo=$(grep -iEw 'key|algorithm' "${keyfile}" | grep -A1 "${kname}" | grep algorithm | awk '{print $2}' | cut -f 1 -d\; | tr -d [\'\"]  )

	if [ -z "${secret}" ]
	then
	      echo "Couldn't find secret for updating"
	      exit 1
	fi
}


for i in $(seq 1 ${NSC} )
do
	auth_ns=${AUTH_NS[$i]}
	kname=${RNDC_KEY[$i]}
	domain=${DOMAIN[$i]}

	# --insecure to ignore cert errors ### THIS IS DANGEROUS, USE ONLY IN TESTING OR EMERGENCIES
	LM=$(curl --silent -I https://mta-sts.${domain}/.well-known/mta-sts.txt 2>/dev/null | grep 'last-modified' | cut -f2- -d:)
	if [ -z "${LM}" ]
	then
		echo "can't determine last modified date of https://mta-sts.${domain}/.well-known/mta-sts.txt"
		exit 1
	fi

	NOW=$(date '+%Y%m%d%H%M%S')
	NEWMTS=$(date '+%Y%m%d%H%M%SZ' --date="${LM}" 2>/dev/null||date '+%Y%m%d%H%M%SZ' --date="${NOW}")

	#just extract the date
	OLDMTS=$(dig +short _mta-sts.${domain}. @${ext_ns} TXT | awk '{print $2}' | cut -f 2 -d= | sed 's/"//g;')

	if [ -n "${NEWMTS}" -a -n "${OLDMTS}" ]
	then
		if [ "${OLDMTS}" != "${NEWMTS}" ]
		then
        		MTSTXT="v=STSv1; id=${NEWMTS}"

			getkey

			[[ -n "${auth_ns}" ]] && nsupdate <<EOF
server ${auth_ns}
key ${algo}:${kname} ${secret}
update delete _mta-sts.${domain}. IN TXT
update add _mta-sts.${domain}. 3600 IN TXT "${MTSTXT}"
send
EOF

		        echo "MTS-STS records updated"
		fi
	else
		echo "failed to update MTS-STS record for ${domain}/${auth_ns}"
	fi
done
