#!/bin/bash
# run this as the bind user (or root, if absoultely necessary)
# based on:  https://blog.apnic.net/2019/05/23/how-to-deploying-dnssec-with-bind-and-ubuntu-server/

BINDROOT=/etc/bind
DBROOT=/var/cache/bind/db
DOMAINLIST=""   # "example.com  example.net  ipv6.example.com"
ZONEFILE_RE="fwd-XXXXXXXX.db"	# script will replace the 8 x's (XXXXXXXX) with the domain name as written

if [ -z "${DOMAINLIST}" ];
then
	echo "edit this to include your domains, then re-run it"
	exit 1
fi

mkdir -p ${BINDROOT}/keys
cd ${BINDROOT}/keys
for DOMAIN in ${DOMAINLIST}
do
	echo "configuring ${DOMAIN}..."

	zonefile=${DBROOT}/${ZONEFILE_RE//XXXXXXXX/$DOMAIN}

	dnssec-keygen -r /dev/urandom -a ECDSAP256SHA256 -n ZONE ${DOMAIN}
	dnssec-keygen -r /dev/urandom -a ECDSAP256SHA256 -fKSK -n ZONE ${DOMAIN}
	chmod g+r *.private

	rndc freeze ${DOMAIN}
	echo "\$ORIGIN ${DOMAIN}" >> ${zonefile}
	cat ${BINDROOT}/keys/K*.key | grep DNSKEY >> ${zonefile}
	rndc thaw ${DOMAIN}
done

echo "these lines need to be added to your ${DOMAIN} zone config manually:"
echo '                key-directory "/etc/bind/keys";'
echo '                auto-dnssec maintain;'
echo '                inline-signing yes;'

echo 'and'

echo 'these lines need to be added to your named.conf.options manually:'
echo '                dnssec-enable yes;'
echo '                dnssec-validation auto;'

echo 'then:'

echo '      rndc reconfig'
echo '      rndc reload'

echo 'afterward:'

echo "add the following DSR's to your registrar's config to complete the configuration"

for DOMAIN in ${DOMAINLIST}
do
	echo "dig @localhost dnskey ${DOMAIN} | dnssec-dsfromkey -f - ${DOMAIN}"
done

echo "format is:  [DOMAIN] IN DS [KEYTAG#] [ALG] [DTYPE] [DIGEST HASH]"

echo "done."
