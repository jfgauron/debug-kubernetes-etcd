#!/bin/bash
set -e

ETCD_VER=v3.2.32
GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
DOWNLOAD_URL=${GITHUB_URL}

sudo -i -u root bash << SUDOEOF
set -e
apt-get update

# Ubuntu 20.04 (ami-0996d3051b72b5b2c)

## Configure iptables
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system


## Setup config files
mv /tmp/config /root/config


## Containerd
apt-get install -y containerd
mkdir -p /etc/containerd
mv /root/config/containerd_config.toml /etc/containerd/config.toml
systemctl restart containerd


## Kubeadm, kubelet, kubectl
apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF | tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl


## etcdctl
mkdir -p /tmp/etcd-download-test
curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar xzvf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/etcd-download-test --strip-components=1
rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
mv /tmp/etcd-download-test/etcd /usr/bin/etcd
mv /tmp/etcd-download-test/etcdctl /usr/bin/etcdctl


## Pull all required images
kubeadm config images pull
ctr -n=k8s.io image pull docker.io/calico/kube-controllers:v3.18.1
ctr -n=k8s.io image pull docker.io/calico/node:v3.18.1
ctr -n=k8s.io image pull docker.io/calico/cni:v3.18.1
ctr -n=k8s.io image pull docker.io/calico/pod2daemon-flexvol:v3.18.1


# We run kubeadm init for 2 reasons:
# 1) It validates that our dependencies are correct
# 2) It downloads all the files we will need locally since our actual node won't be connected to the internet
kubeadm init --upload-certs --config /root/config/kubeadm.yaml
kubeadm reset -f

mv /tmp/scripts /root/scripts
SUDOEOF