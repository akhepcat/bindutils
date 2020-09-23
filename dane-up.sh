#!/bin/bash
### 
###  Updates the TLSA/DANE record to match the defined webserver's TLS certificate
###

host="www-internal"		# internal hostname
cname="www"			# external hostname
domain="example.net"		# domain name
ext_ns="ext-ns.example.net"	# external/slave NS for testing against
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

DANE=$(tlsa -4  --port 443 --insecure ${host}.${domain} 2>&1 | grep TLSA | sed "s/${host}/${cname}/g; s/IN TLSA/3600 IN TLSA/;")
OLDDANE=$(dig +short _443._tcp.${cname}.${domain}. @${ext_ns} TLSA | awk '{print $4}')
OLDDANE=${OLDDANE,,}

if [ -n "${DANE}" -a -z "${DANE##*IN TLSA 3 0 1*}" ]
then

    if [ -n "${DANE##*$OLDDANE*}" ]
    then

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
    echo "failed to update TLSA/DANE record"
    exit 1
fi
