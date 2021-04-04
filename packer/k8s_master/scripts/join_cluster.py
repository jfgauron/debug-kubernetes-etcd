#!/usr/bin/python3
import json
import re
import subprocess
import sys

def run(loadbalancer_dns, token, discovery_hash, certificate_key):
  #run_cmd(["kubeadm", "join", "--token", "--config", "/root/kubeadm.yaml"])

  command = [
    "kubeadm", "join", "%s:6443" % loadbalancer_dns,
    "--token", token,
    "--discovery-token-ca-cert-hash", discovery_hash,
    "--certificate-key", certificate_key,
    "--control-plane",
    "--v=10"
  ]

  output = run_cmd(" ".join(command))

  run_cmd("mkdir -p /root/.kube")
  run_cmd("cp /etc/kubernetes/admin.conf /root/.kube/config")

  return {
    "result": "SUCCESS" if "new control plane instance was created" in output else "ERROR",
    "output": output,
  }

##################################
# Helper methods
##################################
def run_cmd(command):
  process = subprocess.Popen(command, stdout=subprocess.PIPE, shell=True)
  stdout, stderr = process.communicate()
  return stdout.decode('utf-8')
  #return subprocess.run(command, stdout=subprocess.PIPE, shell=True).stdout.decode('utf-8')


if len(sys.argv) < 5:
  result = {"result": "FAILED", "reason": "Missing load balancer dns and/or credentials"}
else:
  result = run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])

print(json.dumps(result))