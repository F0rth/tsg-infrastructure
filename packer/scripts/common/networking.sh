#!/bin/bash

set -e

export PATH='/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin'

source /var/tmp/helpers/default.sh

if ufw status &>/dev/null; then
    ufw disable

    for option in stop disable; do
        systemctl "$option" ufw || true
    done
fi

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Make sure to install the package, as often Amazon image used as the
# source would not have it installed resulting in a failure to bring
# the network interface (eth0) up on boot.
if ! dpkg -s ethtool &>/dev/null; then
    apt_get_update
    apt-get --assume-yes install ethtool
fi

# Based on the original ethtool script, but only sets a number of
# specific offloading settings, should there be none specified.
cat <<'EOF' > /etc/network/if-up.d/ethtool-offload
#!/bin/sh

ETHTOOL=/sbin/ethtool

test -x $ETHTOOL || exit 0

[ "$IFACE" != "lo" ] || exit 0

gather_settings () {
    set | sed -n "
/^IF_$1[A-Za-z0-9_]*=/ {
    h;                             # hold line
    s/^IF_$1//; s/=.*//; s/_/-/g;  # get name without prefix
    y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/;  # lower-case
    p;
    g;                             # restore line
    s/^[^=]*=//; s/^'\(.*\)'/\1/;  # get value
    p;
}"
}

SETTINGS="$(gather_settings OFFLOAD_)"
[ -n "$SETTINGS" ] || SETTINGS="tso off gso off lro off"

$ETHTOOL --offload "$IFACE" $SETTINGS || true
EOF

chown root: /etc/network/if-up.d/ethtool-offload
chmod 755 /etc/network/if-up.d/ethtool-offload
