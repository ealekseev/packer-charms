#!/bin/sh -e

export APT_LISTCHANGES_FRONTEND=none
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confnew" --force-yes -y install cloud-init
