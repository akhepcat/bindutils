#!/bin/bash
###
### This only updates if the existing dmarc rule changes or doesn't exist

if [ ! -r "${0}.local" ]
then
	# Global settings
	ext_ns="ns-cache.example.net"		# external NS for testing
	keyfile="/etc/bind/named.keys"	# Where your keys are located

	# the dmarc rule to use ( defaults include aspf=r and adkim=r; no need to add below, only if 's'trict is required)
	dmarc="v=DMARC1; p=quarantine; sp=quarantine; pct=100; fo=1; rua=mailto:MYACCOUNT@dmarc.report-uri.com; ruf=mailto:MYACCOUNT@dmarc.report-uri.com"

	####
	# Per-host settings

	NSC=$((NSC + 1))		# (auto-increment)		# every DANE record gets a block
	DOMAIN[$NSC]="example.net"	# domain name
	RNDC_KEY[$NSC]="update"		# the name of the key
	AUTH_NS[$NSC]="192.168.1.1"	# The authoritative nameserver

	NSC=$((NSC + 1))		# (auto-increment)		# every DANE record gets a block
	DOMAIN[$NSC]="example.com"	# domain name
	RNDC_KEY[$NSC]="update"		# the name of the key
	AUTH_NS[$NSC]="192.168.2.1"	# The authoritative nameserver

else
	# Read in the setting from the .local config
	. "${0}.local"
fi

NSD="-d -L1"

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

	OLDDMARC=$(dig +short _dmarc.${domain}. @${ext_ns} TXT)
	OLDDMARC=${OLDDMARC//[\'\"]/}

	# only update if it's missing or different
	if [ -z "${OLDDMARC}" -o "${OLDDMARC,,}" != "${dmarc,,}" ]
	then
		getkey

		nsupdate ${NSD} <<EOF
server ${auth_ns}
key ${algo}:${kname} ${secret}
update delete _dmarc.${domain}. IN TXT
update add _dmarc.${domain}. 86400 IN TXT "${dmarc}"
send
EOF
		if [ $? -eq 0 ]
		then
			echo "DMARC record updated"
		else
			echo "failed to update DMARC record for ${domain}/${auth_ns}"
		fi
	fi
done