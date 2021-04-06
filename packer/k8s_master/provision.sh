#!/bin/bash
set -e

ETCD_VER=v3.2.32
GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
DOWNLOAD_URL=${GITHUB_URL}

K8S_VERSION="1.20.5-00"

sudo -i -u root bash << SUDOEOF
set -e

# swapoff -a permanently
swapoff -a
sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

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
apt-get install -qy kubelet=${K8S_VERSION} kubeadm=${K8S_VERSION} kubectl=${K8S_VERSION}
apt-mark hold kubelet kubeadm kubectl


## etcdctl
mkdir -p /tmp/etcd-download-test
curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar xzvf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/etcd-download-test --strip-components=1
rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
mv /tmp/etcd-download-test/etcd /usr/bin/etcd
mv /tmp/etcd-download-test/etcdctl /usr/bin/etcdctl


## Pull all required images
kubeadm config images pull --kubernetes-version stable-1.19
# ctr -n=k8s.io image pull docker.io/calico/kube-controllers:v3.18.1
# ctr -n=k8s.io image pull docker.io/calico/node:v3.18.1
# ctr -n=k8s.io image pull docker.io/calico/cni:v3.18.1
# ctr -n=k8s.io image pull docker.io/calico/pod2daemon-flexvol:v3.18.1


# We run kubeadm init for 2 reasons:
# 1) It validates that our dependencies are correct
# 2) It downloads all the files we will need locally since our actual node won't be connected to the internet
kubeadm init --upload-certs --config /root/config/kubeadm.yaml
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
kubectl apply -f /root/config/calico.yaml
kubeadm reset -f
rm -rf /etc/cni
rm -rf /root/.kube

mv /tmp/scripts /root/scripts
SUDOEOF