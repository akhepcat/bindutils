# bindutils
Assortment of utilities to help with automating bind updates

* mtasts-up.sh - Updates MTA-STS records for your authoritative name servers

* dane-up.sh   - Updates your DANE/TLSA records for your domain

* dmarc-up.sh  - Updates your DMARC records for your domain

* svs-upd-cron.sh - Drop this in /etc/cron.weekly, and the above three scripts in /etc/bind, chmod +x, and $PROFIT$
