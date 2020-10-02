#!/bin/bash
### 
###  Updates the TLSA/DANE record to match the defined webserver's TLS certificate
###

# Global settings
ext_ns="ns-cache.example.net"		# external NS for testing
keyfile="/etc/bind/named.keys"	# Where your keys are located

####

NSC=$((NSC + 1))		# (auto-increment)		# every DANE record gets a block
HOST[$NSC]="prodweb"		# internal hostname
CNAME[$NSC]="www"		# external hostname
DOMAIN[$NSC]="example.net"	# domain name
RNDC_KEY[$NSC]="update"		# the name of the key
AUTH_NS[$NSC]="192.168.1.1"	# The authoritative nameserver


NSC=$((NSC + 1))		# (auto-increment)		# every DANE record gets a block
HOST[$NSC]="devweb"		# internal hostname
CNAME[$NSC]="www-dev"		# external hostname
DOMAIN[$NSC]="example.com"	# domain name
RNDC_KEY[$NSC]="dev-update"	# the name of the key
AUTH_NS[$NSC]="192.168.2.1"	# The authoritative nameserver

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
	host=${HOST[$i]}
	cname=${CNAME[$i]}
	auth_ns=${AUTH_NS[$i]}
	kname=${RNDC_KEY[$i]}
	domain=${DOMAIN[$i]}

	DANE=$(tlsa -4  --port 443 --insecure ${host}.${domain} 2>&1 | grep TLSA | sed "s/${host}/${cname}/g; s/IN TLSA/3600 IN TLSA/;")
	OLDDANE=$(dig +short _443._tcp.${cname}.${domain}. @${ext_ns} TLSA | awk '{print $4}')
	OLDDANE=${OLDDANE,,}

	if [ -n "${DANE}" -a -z "${DANE##*IN TLSA 3 0 1*}" ]
	then

		if [ -n "${DANE##*$OLDDANE*}" ]
		then
			getkey

			nsupdate <<EOF
server ${auth_ns}
key ${algo}:${kname} ${secret}
update delete _443._tcp.${cname}.${domain}. IN TLSA
update add ${DANE}
send
EOF
	 	       echo "TLSA/DANE record updated"
		fi
	else
		echo "failed to update TLSA/DANE record for ${domain}/${auth_ns}"
	fi
done
