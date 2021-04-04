Requires `packer`, `terraform`, and `jq`

**1. Setup ssh-agent**

Required to ssh from bastion to private control plane nodes.
```
killall ssh-agent
eval `ssh-agent`
ssh-add ~/.ssh/id_rsa
```

**2. Build the ami**

`./run_packer.sh` will build the ami with all the dependencies to manage a k8s cluster using `packer`. It takes about 7-8 minutes.
```
./run_packer.sh
```

**3. Init Terraform modules**
```
terraform init
```

**4. Build infrastructure**
```
./clean.sh # Ignore errors
terraform apply
```

`terraform apply` will launch the instances, the load balancer, and everything else required for the cluster to run. It takes about 4 minutes the first time, 2 minutes when you retry building just the masters instances.

**5. Store terraform output in variables**
```
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
```

**6. Init Cluster**

Initializing the cluster takes about 2-3 minutes.

```
INIT_RESULT=`$EXEC_MASTER1 sudo python3 /root/scripts/init_cluster.py $LB_DNS`
echo $INIT_RESULT | jq
```

The output should look something like:
```
{
  "result": "SUCCESS",
  "cluster_data": {
    "LoadBalancerDNS": "k8s-control-plane-lb-2b373aca856dd6c7.elb.us-east-2.amazonaws.com",
    "Credentials": {
      "Token": "gfk4k2.r0tnbuavjva95hh3",
      "DiscoveryHash": "sha256:052bdabf4ac9a1371df84cd5ca3bc9c915383dffa33b46dae0ede57e8f5e8dea",
      "CertificateKey": "4560e60c7968d3091c23feebba0ec114b702af01ffd91b5386f87742cc0d941b"
    }
  }
}
```

**7. Store credentials in variables**
```
TOKEN=`echo $INIT_RESULT | jq '.cluster_data.Credentials.Token' -r`
DISCOVERY_HASH=`echo $INIT_RESULT | jq '.cluster_data.Credentials.DiscoveryHash' -r`
CERTIFICATE_KEY=`echo $INIT_RESULT | jq '.cluster_data.Credentials.CertificateKey' -r`
```

**8. Join Cluster**
```
JOIN_RESULT=`$EXEC_MASTER2 sudo python3 /root/scripts/join_cluster.py $LB_DNS $TOKEN $DISCOVERY_HASH $CERTIFICATE_KEY`
echo $JOIN_RESULT | jq
```

If the output contains `"result": "SUCCESS"`, it means the node successfully joined the cluster. Repeat step 4 to 8 to try and get a failure. In my experience, there is about a 50% chance of success. When the join command fails, you'll start seeing error output such as:

```
Failed to get etcd status for https://10.17.3.31:2379: failed to dial endpoint https://10.17.3.31:2379 with maintenance client: context deadline exceeded
```

If you want to SSH into master1 (where the cluster was initialized) or master2 (the node trying to join), run:
```
$SHELL_MASTER1 # or...
$SHELL_MASTER2
```