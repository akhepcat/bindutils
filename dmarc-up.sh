#!/bin/bash
###
### This only updates if the existing dmarc rule changes or doesn't exist

# the dmarc rule to use ( defaults include aspf=r and adkim=r; no need to add below, only if 's'trict is required)
dmarc="v=DMARC1; p=quarantine; sp=quarantine; pct=100; fo=1; rua=mailto:MYACCOUNT@dmarc.report-uri.com; ruf=mailto:MYACCOUNT@dmarc.report-uri.com"

domain="example.net"		# local domain name
ext_ns="ext-ns.example.net"	# external NS for testing against
auth_ns="192.168.1.1"		# The authoritative nameserver
keyfile="/etc/bind/named.keys"	# Where your keys are located
kname="update"			# the name of the key

######

secret=$(grep -iEw 'key|secret' "${keyfile}" | grep -A1 "${kname}" | grep secret | awk '{print $2}' | cut -f 1 -d\; | tr -d [\'\"]  )
algo=$(grep -iEw 'key|algorithm' "${keyfile}" | grep -A1 "${kname}" | grep algorithm | awk '{print $2}' | cut -f 1 -d\; | tr -d [\'\"]  )

if [ -z "${secret}" ]
then
      echo "Couldn't find secret for updating"
      exit 1
fi

OLDDMARC=$(dig +short _dmarc.${domain}. @${ext_ns} TXT)
OLDDMARC=${OLDDMARC//[\'\"]/}

# only update if it's missing or different
if [ -z "${OLDDMARC}" -o "${OLDDMARC}" != "${dmarc}" ]
then
        nsupdate <<EOF
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
		echo "failed to update DMARC record"
		exit 1
	fi
fi
