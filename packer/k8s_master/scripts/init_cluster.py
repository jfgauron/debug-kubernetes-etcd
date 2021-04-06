#!/usr/bin/python3
import json
import re
import subprocess
import sys
import time

def run(load_balancer_dns):
  cluster_data = {
    "LoadBalancerDNS": load_balancer_dns
  }

  # update /root/config/kubeadm.yaml
  update_config_with_dns(load_balancer_dns)

  # run kubeadm init
  init_output = run_cmd("kubeadm init --upload-certs --config /root/config/kubeadm.yaml --v=10")
  if "initialized successfully!" not in init_output:
    return {
      "result": "FAILED",
      "reason": init_output,
    }

  # extract creds
  cluster_data["Credentials"] = extract_creds(init_output)

  # apply cni
  run_cmd("mkdir -p /root/.kube")
  run_cmd("cp /etc/kubernetes/admin.conf /root/.kube/config")
  cni_output = run_cmd("kubectl apply -f /root/config/calico.yaml")
  if "created" not in cni_output:
    return {
      "result": "CNI_FAILED",
      "cni_output": cni_output,
      "init_output": init_output,
      "cluster_data": cluster_data
    }

  return {
    "result": "SUCCESS",
    "cni_output": cni_output,
    "init_output": init_output,
    "cluster_data": cluster_data,
  }

##################################
# Helper methods
##################################
def run_cmd(command):
  return subprocess.run(command + " 2>&1", stdout=subprocess.PIPE, shell=True).stdout.decode('utf-8')

def update_config_with_dns(load_balancer_dns):
  run_cmd("sed -i s/{{LOAD_BALANCER_DNS}}/%s/g /root/config/kubeadm.yaml" % load_balancer_dns)
  run_cmd("sed -i s/#controlPlaneEndpoint/controlPlaneEndpoint/g /root/config/kubeadm.yaml")

def extract_creds(init_output):
  token = re.search("join .+ --token (.+?)\s", init_output).group(1).strip()
  discovery_hash = re.search("--discovery-token-ca-cert-hash (.+?)\s", init_output).group(1).strip()
  certificate_key = re.search("--certificate-key (.+?)\s", init_output).group(1).strip()
  return {"Token": token, "DiscoveryHash": discovery_hash, "CertificateKey": certificate_key}



if len(sys.argv) < 2:
  result = {"result": "FAILED", "reason": "Missing load balancer dns argument."}
else:
  result = run(sys.argv[1])

print(json.dumps(result))