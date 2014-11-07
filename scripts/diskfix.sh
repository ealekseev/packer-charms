#!/bin/sh -ex

echo -n "o
n
p
1


a
1
w
" | fdisk -u /dev/sda || partprobe /dev/sda
resize2fs /dev/sda1
