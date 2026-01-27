#!/bin/bash

# Configuration
MASTER_NAME="k3s-master-01"
WORKER_PREFIX="k3s-worker"
WORKER_COUNT=3
SSH_KEY=$(cat ~/.ssh/id_rsa.pub)

# Create cloud-init file from template
sed "s|{{ SSH_KEY }}|$SSH_KEY|g" cloud-init.yaml.tmpl > cloud-init.yaml

echo "Creating VMs (this might take a few minutes)..."
multipass launch --name $MASTER_NAME --cpus 2 --memory 2G --disk 10G --cloud-init cloud-init.yaml 22.04

for i in $(seq 1 $WORKER_COUNT); do
    NAME="${WORKER_PREFIX}-0${i}"
    multipass launch --name $NAME --cpus 1 --memory 3G --disk 10G --cloud-init cloud-init.yaml 22.04
done

echo "Waiting for VMs to be ready..."
# No longer need wait as they are sequential

echo "Fetching IPs and Generating Ansible Inventory..."
MASTER_IP=$(multipass info $MASTER_NAME --format csv | grep $MASTER_NAME | cut -d ',' -f 3)

# Start generating inventory.ini
cat <<EOF > inventory.ini
[master]
$MASTER_NAME ansible_host=$MASTER_IP ansible_user=ubuntu

[workers]
EOF

# Fetch worker IPs
for i in $(seq 1 $WORKER_COUNT); do
    NAME="${WORKER_PREFIX}-0${i}"
    W_IP=$(multipass info $NAME --format csv | grep $NAME | cut -d ',' -f 3)
    echo "$NAME ansible_host=$W_IP ansible_user=ubuntu" >> inventory.ini
done

cat <<EOF >> inventory.ini

[k3s_cluster:children]
master
workers
EOF

# Detect Network Interface
INTERFACE=$(multipass exec $MASTER_NAME -- ip route get 1 | awk '{print $5;exit}')

# Update variables in group_vars/all.yml
SUBNET=$(echo $MASTER_IP | cut -d "." -f 1-3)
VIP="${SUBNET}.100"

# Note: We add placeholders for GitHub Runner variables here
cat <<EOF > group_vars/all.yml
---
k3s_version: v1.31.5+k3s1
ansible_user: ubuntu
kube_vip_address: "$VIP"
network_interface: "$INTERFACE"

# GitHub Runner Configuration
github_repo_url: "https://github.com/YOUR_USER/k3s-services-deploy"
github_runner_token: "YOUR_TOKEN_HERE"
EOF

# Fetch and patch Kubeconfig
echo "Fetching Kubeconfig..."
mkdir -p ~/.kube
multipass exec $MASTER_NAME sudo cat /etc/rancher/k3s/k3s.yaml > k3s_multipass.yaml
sed -i '' "s/127.0.0.1/$MASTER_IP/g" k3s_multipass.yaml

echo ""
echo "Configuration Ready!"
echo "Master IP: $MASTER_IP"
echo "Target VIP: $VIP"
echo "Interface: $INTERFACE"
echo "---------------------------------------"
echo "Next step: ansible-playbook playbook.yml"
echo "---------------------------------------"
