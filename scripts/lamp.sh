#!/bin/bash -xe

date "+%Y-%m-%d %H:%M:%S"
apt-get update
apt-get -y --force-yes install software-properties-common jq curl

add-apt-repository --yes ppa:juju/stable
apt-get -y --force-yes update
apt-get -y --force-yes install juju-core sudo lxc git-core aufs-tools mysql-client
useradd -G sudo -s /bin/bash -m -d /home/ubuntu ubuntu
mkdir -p /root/.ssh
test -f /root/.ssh/juju || ssh-keygen -t rsa -b 4096 -f /root/.ssh/juju -N ''
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-cloud-init-users"
lxc-info -n trusty-base || lxc-create -t ubuntu-cloud -n trusty-base -- -r trusty -S /root/.ssh/juju

lxc-info -n juju || lxc-clone -s -B aufs trusty-base juju
lxc-info -n mysql || lxc-clone -s -B aufs trusty-base mysql
lxc-info -n frontend || lxc-clone -s -B aufs trusty-base frontend

for d in juju mysql frontend; do
  lxc-start -d -n $d;
done

for d in juju mysql frontend; do
  while (true) ; do
    if [ "$(lxc-info -n $d -i awk '{print $2}')" != "" ]; then
        break
    fi
    sleep 10s;
  done
done

sleep 60s;

for d in juju mysql frontend; do
    lxc-attach -n $d -- /usr/bin/ssh-keygen -A
    lxc-attach -n $d -- /usr/sbin/service ssh restart
    lxc-attach -n $d -- mkdir -p /home/ubuntu/.ssh/
    cat /root/.ssh/juju.pub > /var/lib/lxc/$d/delta0/home/ubuntu/.ssh/authorized_keys
    grep -q "lxc.start.auto" /var/lib/lxc/$d/config || echo "lxc.start.auto = 1" >> /var/lib/lxc/$d/config
    grep -q "lxc.start.delay" /var/lib/lxc/$d/config || echo "lxc.start.delay = 5" >> /var/lib/lxc/$d/config
done

mkdir -p /home/ubuntu/.ssh/
cat /root/.ssh/juju.pub >> /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu /home/ubuntu

juju generate-config
juju switch manual

JUJU_IP=$(lxc-info -n juju -i | awk '{print $2}')
FE_IP=$(lxc-info -n frontend -i | awk '{print $2}')
MYSQL_IP=$(lxc-info -n mysql -i | awk '{print $2}')

cat <<_EOF_ > /root/.juju/environments.yaml
default: manual

lxc-clone: true
lxc-clone-aufs: true

environments:
  manual:
    type: manual
    bootstrap-host: ${JUJU_IP}
    lxc-clone: true
    lxc-clone-aufs: true
  local:
    type: local
    default-series: trusty
    lxc-clone: true
    lxc-clone-aufs: true
_EOF_

mkdir -p /root/.juju/ssh/
cp /root/.ssh/juju /root/.juju/ssh/juju_id_rsa
cp /root/.ssh/juju.pub /root/.juju/ssh/juju_id_rsa.pub 

juju bootstrap --debug

juju add-machine ssh:ubuntu@10.0.3.1 #1
juju add-machine ssh:ubuntu@${FE_IP} #2
juju add-machine ssh:ubuntu@${MYSQL_IP} #3

mkdir -p charms/trusty
test -d charms/trusty/mysql || git clone -b trusty https://github.com/vtolstov/charm-mysql charms/trusty/mysql
test -d charms/trusty/lamp || git clone https://github.com/charms/lamp.git charms/trusty/lamp
juju deploy --repository=charms/ local:trusty/mysql --to 3 || juju deploy --repository=charms/ local:trusty/mysql --to 3 || exit 1;
test -d charms/trusty/haproxy || git clone -b trusty https://github.com/vtolstov/charm-haproxy charms/trusty/haproxy
juju set mysql dataset-size=50%
juju set mysql query-cache-type=ON
juju set mysql query-cache-size=-1
juju deploy --repository=charms/ local:trusty/lamp --to 2 || juju deploy --repository=charms/ local:trusty/lamp --to 2 || exit 1;

juju deploy --repository=charms/ local:trusty/haproxy --to 1 || juju deploy --repository=charms/ local:trusty/haproxy --to 1 || exit 1;
juju add-relation haproxy lamp


for s in mysql lamp haproxy; do
    while true; do
        juju status $s/0 --format=json| jq ".services.$s.units" | grep -q 'agent-state' && break
        echo "waiting 5s"
        sleep 5s
    done
done

#iptables -t nat -A PREROUTING -i eth0 -p tcp -m tcp --dport 80 -j DNAT --to-destination ${FE_IP}:80
#iptables -A FORWARD -i eth0 -d ${FE_IP} -p tcp --dport 80 -j ACCEPT


while true; do
    curl -L -s http://${FE_IP} 2>&1 | grep -q "Apache" && break
    echo "waiting 5s"
    sleep 5s
done

date "+%Y-%m-%d %H:%M:%S"

fstrim -v /
