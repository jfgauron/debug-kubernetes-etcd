Various logs that I think are relevant to help diagnose the problem. Master1 is the init node, master2 is the joining node.

`init_output.txt`: Output from running `kubeadm init --v=10`.

`join_output.txt`: Output from running `kubeadm join --v=10`.

`cni_output.txt`: Output from running `kubeadm apply -f /root/config/calico.yaml`.

`kubelet-master1.log`: Output from running `journalctl -xeu kubelet` on master1.

`kubelet-master2.log`: Output from running `journalctl -xeu kubelet` on master2.

`logs-master1.tar.gz`: Entire content of `/var/log/pods` on master1.

`logs-master2.tar.gz`: Entire content of `/var/log/pods` on master2.