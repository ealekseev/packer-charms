#!/bin/sh -ex

apt-get -y --force-yes update
apt-get -y --force-yes dist-upgrade
apt-get -y --force-yes install curl

cat <<EOF > /etc/fstab
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>          <options>                        <dump>  <pass>
/dev/sda1       /               ext4    defaults,relatime,discard,errors=panic      0       1
EOF

export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true
dpkg-reconfigure grub-pc

cat <<EOF > /etc/resolv.conf
nameserver 2001:4860:4860::8888
nameserver 2001:4860:4860::8844
nameserver 8.8.8.8
nameserver 8.8.4.4
options timeout:2 attempts:1 rotate
EOF

cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet6 auto
iface eth0 inet dhcp
dns-nameservers 2001:4860:4860::8888 2001:4860:4860::8844 8.8.8.8 8.8.4.4

EOF
