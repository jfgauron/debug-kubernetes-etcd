#!/bin/bash
set -e

MAX_TRIES=10

# Required to ssh from bastion to private control plane nodes.
killall ssh-agent
eval `ssh-agent`
ssh-add ~/.ssh/id_rsa

# Build the ami
./run_packer.sh

# Init Terraform modules
terraform init

success=0
for i in $(seq 1 $MAX_TRIES)
do
  echo "Time: `date +'%T'`"
  ./clean.sh || true # Ignore errors
  terraform apply -auto-approve

  BASTION=`terraform output bastion | sed -e 's/^"//' -e 's/"$//'`
  MASTER1=`terraform output master1 | sed -e 's/^"//' -e 's/"$//'`
  MASTER2=`terraform output master2 | sed -e 's/^"//' -e 's/"$//'`
  LB_DNS=`terraform output lb_dns | sed -e 's/^"//' -e 's/"$//'`
  EXEC_BASTION="ssh -A -oStrictHostKeyChecking=no ubuntu@$BASTION"
  EXEC_MASTER1="$EXEC_BASTION ssh -oStrictHostKeyChecking=no ubuntu@$MASTER1"
  EXEC_MASTER2="$EXEC_BASTION ssh -oStrictHostKeyChecking=no ubuntu@$MASTER2"
  SHELL_BASTION="ssh -A -t -oStrictHostKeyChecking=no ubuntu@$BASTION"
  SHELL_MASTER1="$SHELL_BASTION ssh -oStrictHostKeyChecking=no ubuntu@$MASTER1"
  SHELL_MASTER2="$SHELL_BASTION ssh -oStrictHostKeyChecking=no ubuntu@$MASTER2"

  sleep 15 # Give some time for ssh to become ready
  mkdir -p "outputs/test-$i"

  $EXEC_MASTER1 "sudo python3 /root/scripts/init_cluster.py $LB_DNS > /tmp/init.txt"
  INIT_RESULT=`$EXEC_BASTION cat /tmp/init.txt`
  echo $INIT_RESULT | jq '' > "outputs/test-$i/init.json"
  cat "outputs/test-$i/init.json" | jq '.init_output' -r > "outputs/test-$i/init_output.txt"
  cat "outputs/test-$i/init.json" | jq '.cni_output' -r > "outputs/test-$i/cni_output.txt"
  cat "outputs/test-$i/init.json" | jq '.cluster_data' -r > "outputs/test-$i/cluster_data.txt"
  echo $INIT_RESULT | jq '.cluster_data'

  if [[ "$INIT_RESULT" == *"FAILED"* ]]; then
    echo "ERROR, will try to fix"
    fixed=false
    for j in $(seq 1 $MAX_TRIES)
    do
      FIX_RESULT=`$EXEC_MASTER1 sudo kubectl apply -f /root/config/calico.yaml` || true
      if [[ "$FIX_RESULT" != *"connection to the server"* ]]; then
        fixed=true
        break
      fi
      echo "Not fixed ($j / $MAS_TRIES)"
      sleep 10
    done
    if [ "$fixed" = false ] ; then
        echo "FAILED! ($success / $i)"
        continue
    fi
  fi

  TOKEN=`echo $INIT_RESULT | jq '.cluster_data.Credentials.Token' -r`
  DISCOVERY_HASH=`echo $INIT_RESULT | jq '.cluster_data.Credentials.DiscoveryHash' -r`
  CERTIFICATE_KEY=`echo $INIT_RESULT | jq '.cluster_data.Credentials.CertificateKey' -r`

  $EXEC_MASTER2 "sudo python3 /root/scripts/join_cluster.py $LB_DNS $TOKEN $DISCOVERY_HASH $CERTIFICATE_KEY > /tmp/join.txt"
  JOIN_RESULT=`$EXEC_BASTION cat /tmp/join.txt`
  echo $JOIN_RESULT | jq '' > "outputs/test-$i/join.json"
  cat "outputs/test-$i/join.json" | jq '.output' -r > "outputs/test-$i/join_output.txt"

  if [[ "$JOIN_RESULT" == *"This node has joined the cluster and a new control plane instance was created"* ]]; then
    ((success=success+1))
    echo "SUCCESS! (status: $success / $i)"
  else
    echo "FAILED! (status: $success / $i)"
  fi
done