#!/bin/bash

# Configuration
MASTER_NAME="k3s-master-01"
WORKER_PREFIX="k3s-worker"
WORKER_COUNT=3
SSH_KEY=$(cat ~/.ssh/id_rsa.pub 2>/dev/null || cat ~/.ssh/id_ed25519.pub 2>/dev/null)

if [ -z "$SSH_KEY" ]; then
    echo "Error: No SSH public key found in ~/.ssh/id_rsa.pub or ~/.ssh/id_ed25519.pub"
    exit 1
fi

# Cleanup existing VMs
echo "Cleaning up existing VMs..."
multipass delete $MASTER_NAME 2>/dev/null
for i in $(seq 1 $WORKER_COUNT); do
    NAME="${WORKER_PREFIX}-0${i}"
    multipass delete $NAME 2>/dev/null
done
echo "Purging deleted VMs..."
multipass purge
echo "Cleanup complete."

# Create cloud-init file from template
cat <<EOF > cloud-init.yaml
#cloud-config
ssh_authorized_keys:
  - $SSH_KEY
sudo: ['ALL=(ALL) NOPASSWD:ALL']
groups: [sudo]
shell: /bin/bash
EOF

echo "Creating VMs (this might take a few minutes)..."
echo "Launching $MASTER_NAME (2 CPUs, 3G RAM)..."
multipass launch --name $MASTER_NAME --cpus 2 --memory 3G --disk 10G --cloud-init cloud-init.yaml 22.04

for i in $(seq 1 $WORKER_COUNT); do
    NAME="${WORKER_PREFIX}-0${i}"
    echo "Launching $NAME (1 CPU, 3G RAM)..."
    # Added a small sleep to avoid overlapping heavy initialization
    sleep 2
    multipass launch --name $NAME --cpus 1 --memory 3G --disk 10G --cloud-init cloud-init.yaml 22.04
done

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

# VIP setup (Point to Master IP for dev)
VIP=$MASTER_IP

# GitHub Runner Configuration
if [ -z "$GITHUB_RUNNER_TOKEN" ]; then
    echo "Warning: GITHUB_RUNNER_TOKEN not set. GitHub Runner will NOT be configured."
    RUNNER_TOKEN="NONE"
else
    RUNNER_TOKEN="$GITHUB_RUNNER_TOKEN"
fi

# Update variables in group_vars/all.yml
mkdir -p group_vars
cat <<EOF > group_vars/all.yml
---
k3s_version: v1.31.5+k3s1
ansible_user: ubuntu
kube_vip_address: "$VIP"
network_interface: "$INTERFACE"

# GitHub Runner Configuration
github_repo_url: "https://github.com/YOUR_USER/k3s-services-deploy"
github_runner_token: "$RUNNER_TOKEN"
EOF

echo ""
echo "Configuration Ready!"
echo "Master IP: $MASTER_IP"
echo "Target VIP: $VIP"
echo "Interface: $INTERFACE"
echo "---------------------------------------"
echo "Next step: ansible-playbook playbook.yml"
echo "---------------------------------------"
