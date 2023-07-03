
### 
###  Updates the TLSA/DANE record to match the defined webserver's TLS certificate
###

## More specifically, it is RECOMMENDED that at most sites TLSA records published for DANE servers
##    be “DANE-EE(3) SPKI(1) SHA2-256(1)”  records.
##
## Selector SPKI(1) is chosen because it is compatible with
## raw public keys [RFC7250] and the resulting TLSA record need not
## change across certificate renewals with the same key.
##
## Matching type SHA2-256(1) is chosen because all DANE implementations are required
## to support SHA2-256.
##
## This TLSA record type easily supports hosting arrangements with a single certificate
## matching all hosted domains. It is also the easiest to implement correctly in the client. [RFC 7671]


if [ ! -r "${0}.local" ]
then
	# Global settings
	ext_ns="ns-cache.example.net"		# external NS for testing
	keyfile="/etc/bind/named.keys"	# Where your keys are located

	####

	NSC=$((NSC + 1))		# (auto-increment)		# every DANE record gets a block
	HOST[$NSC]="prodweb"		# internal hostname
	CNAME[$NSC]="www"		# external hostname
	ASDOMAIN[$NSC]=1		# This domain's CNAME is equal to the bare domain
	PORTS[$NSC]="25 443"		# we want SMTP/starttls and HTTPS
	DOMAIN[$NSC]="example.net"	# domain name
	RNDC_KEY[$NSC]="update"		# the name of the key
	AUTH_NS[$NSC]="192.168.1.1"	# The authoritative nameserver
	NOTIFY[$NSC]="192.168.1.1"	# Nameserver to trigger notifies on
	VIEW[$NSC]="in external"	# This nameserver has views, we need the external view

	NSC=$((NSC + 1))		# (auto-increment)		# every DANE record gets a block
	HOST[$NSC]="devweb"		# internal hostname
	CNAME[$NSC]="www-dev"		# external hostname
	ASDOMAIN[$NSC]=0		# This domain's CNAME is NOT equal to the bare domain (default)
	PORTS[$NSC]="443"		# we want only HTTPS
	DOMAIN[$NSC]="example.com"	# domain name
	RNDC_KEY[$NSC]="dev-update"	# the name of the key
	AUTH_NS[$NSC]="192.168.2.1"	# The authoritative nameserver
	NOTIFY[$NSC]="192.168.1.1"	# Nameserver to trigger notifies on
	VIEW[$NSC]=""			# This nameserver doesn't have views
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
	cname=${CNAME[$i]}
	host=${HOST[$i]} ; host=${host:-$cname}
	auth_ns=${AUTH_NS[$i]}
	kname=${RNDC_KEY[$i]}
	domain=${DOMAIN[$i]}
	ports=${PORTS[$i]}
	wasd=${ASDOMAIN[$i]}

	for port in ${ports}
	do

	    case ${port} in
		21) POPT="--port ${port} --starttls ftp" ;;
		25) POPT="--port ${port} --starttls smtp" ;;
		110) POPT="--port ${port} --starttls pop3" ;;
		143) POPT="--port ${port} --starttls imap" ;;
		*) POPT="--port ${port}" ;;
	    esac

	    hname="${host:+$host.}${domain}"
	    xname="${cname:+$cname.}${domain}"
	    DANE=$(tlsa --usage 3 --selector 1 --mtype 1 ${POPT} --insecure ${hname} 2>&1 | grep TLSA | sed "s/${host}/${cname}/g; s/IN TLSA/3600 IN TLSA/;")
	    OLDDANE=$(dig +short _${port}._tcp.${xname}. @${ext_ns} TLSA | awk '{print $4}')
	    OLDDANE=${OLDDANE,,}

	    if [ -n "${DANE}" -a -z "${DANE##*IN TLSA 3 1 1*}" ]
	    then

		# $FORCE is read from the cli env if you need it
		if [ -n "${DANE##*$OLDDANE*}" -o ${FORCE:-0} -eq 1 ]
		then
			getkey

			nsupdate ${NSD} <<EOF
server ${auth_ns}
key ${algo}:${kname} ${secret}
update delete _${port}._tcp.${cname}.${domain}. IN TLSA
send
update add ${DANE}
send
EOF
			if [ ${wasd:-0} -eq 1 ]
			then
				# fix-up the DANE record for the bare domain
				DANE="${DANE//${cname}./}"
				nsupdate ${NSD} <<EOF
server ${auth_ns}
key ${algo}:${kname} ${secret}
update delete _${port}._tcp.${domain}. IN TLSA
send
update add ${DANE}
send
EOF

			fi
			echo "TLSA/DANE records for ${domain}:${port} updated"
			NEEDSYNC=1
		fi
	    else
		echo "failed to update TLSA/DANE record for ${host}.${domain}:${port}/${auth_ns}"
	    fi

	# ports loop
	done
done

if [ ${NEEDSYNC:-0} -eq 1 ]
then
	# Uniquely trigger nameserver sync's
	for i in $(seq 1 ${NSC} )
	do
		NS=${AUTH_NS[$i]}
		NSS=${NS//./}
		SAW=${SEEN[$NSS]}
		if [ ${SAW:-0} -ne 1 ]
		then
			NNS=${NOTIFY[$i]}
			rndc -s ${NNS} notify ${DOMAIN[$i]} ${VIEW[$i]}
			SEEN[${NSS}]=1
		fi
	done
fi
