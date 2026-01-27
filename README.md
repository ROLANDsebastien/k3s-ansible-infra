# 🏗️ K3s Infrastructure (HA Cluster)

This project automates the creation of a High-Availability K3s cluster using Multipass and Ansible.

## 📋 Prerequisites
- Multipass
- Ansible

## 🚀 Quick Start

1. **Provision VMs:**
   ```bash
   ./setup_multipass.sh
   ```

2. **Run Ansible Playbook:**
   ```bash
   ansible-playbook playbook.yml
   ```

3. **Get Kubeconfig:**
   Follow the instructions in the terminal output to fetch `k3s_multipass.yaml`.

## 🏗️ Architecture
- **Master:** `k3s-master-01` (Tainted, No workloads).
- **Workers:** 3 nodes for application deployment.
- **VIP:** Managed by `kube-vip` for a stable API endpoint.
