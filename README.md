# K8s GitOps Platform

A production-grade Kubernetes platform on AWS with GitOps, monitoring, and automated configuration management.

## GitOps Workflow

```
Developer pushes code to GitHub
           │
           ▼
   GitHub Repository
  (K8s-GitOps-Platform)
           │
           ▼
     ArgoCD detects
       changes
           │
           ▼
  ArgoCD syncs Helm charts
  from k8s-gitops-config repo
    to EKS cluster
           │
           ▼
  Kubernetes deploys/updates
      microservices
           │
           ▼
  Prometheus scrapes metrics
           │
           ▼
  Grafana displays dashboards
           │
           ▼
  AlertManager sends alerts
```

## Repositories

| Repository | Purpose |
|-----------|---------|
| [K8s-GitOps-Platform](https://github.com/Aishwini08/K8s-GitOps-Platform) | Infrastructure (Terraform), ArgoCD manifests, monitoring config, Ansible playbooks |
| [k8s-gitops-config](https://github.com/Aishwini08/k8s-gitops-config) | Helm charts watched by ArgoCD |

## Project Structure

```
k8s-gitops-platform/
├── microservices/
│   ├── service1-node/        # Node.js service (port 3000)
│   ├── service2-python/      # Python/Flask service (port 5000)
│   └── service3-go/          # Go service (port 8080)
├── helm-charts/
│   ├── node-service/         # Helm chart for Node.js
│   ├── python-service/       # Helm chart for Python
│   └── go-service/           # Helm chart for Go
├── argocd/
│   └── apps/                 # ArgoCD Application manifests
├── ansible/
│   ├── inventory/            # Static + dynamic inventory
│   ├── roles/
│   │   ├── os-hardening/     # SSH hardening, file permissions
│   │   ├── node-setup/       # Kernel modules, sysctl, packages
│   │   ├── containerd/       # Container runtime setup
│   │   ├── node-exporter/    # Prometheus Node Exporter
│   │   ├── prometheus-config/ # Prometheus scrape config
│   │   └── alertmanager-config/ # AlertManager configuration
│   └── site.yml              # Master playbook
├── monitoring/
│   ├── grafana-dashboards/   # Custom Grafana dashboard ConfigMaps
│   └── alertmanager-values.yaml  # Prometheus stack Helm values
├── rbac/
│   ├── namespaces.yaml
│   ├── production-rbac.yaml
│   └── staging-rbac.yaml
└── k8s-terraform/
    ├── modules/
    │   ├── vpc/              # VPC, subnets, NAT, bastion, key pair
    │   └── eks/              # EKS cluster, node groups
    └── main.tf
```

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- kubectl
- Helm >= 3.0
- Ansible >= 2.16 (via WSL on Windows)
- Docker

## Deployment Guide

### 1. Provision Infrastructure

```bash
cd k8s-terraform
terraform init
terraform apply -auto-approve
```

This creates:
- VPC with public/private subnets
- NAT Gateway
- Bastion host (for Ansible access)
- EKS cluster (v1.32) with 2 worker nodes (t3.medium)
- SSH key pair — saved automatically as `k8s-terraform/my-eks-key.pem`

### 2. Connect kubectl

```bash
aws eks update-kubeconfig --region ap-south-1 --name my-eks-cluster
kubectl get nodes
```

### 3. Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Get admin password (PowerShell):
```powershell
$encoded = kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encoded))
```

Access ArgoCD UI at https://localhost:8080 — username: `admin`

### 4. Deploy Microservices via ArgoCD

> **Note:** ArgoCD watches the separate **[k8s-gitops-config](https://github.com/Aishwini08/k8s-gitops-config)** repository for Helm chart changes.

```bash
kubectl apply -f argocd/apps/
kubectl get applications -n argocd
```

### 5. Configure Worker Nodes with Ansible

> Run from WSL on Windows.

```bash
# Copy PEM key to WSL
cp /mnt/c/Users/<username>/Pictures/k8s-gitops-platform/k8s-terraform/my-eks-key.pem ~/my-eks-key.pem
chmod 400 ~/my-eks-key.pem

cd /mnt/c/Users/<username>/Pictures/k8s-gitops-platform/ansible
ansible-playbook -i inventory/hosts.ini site.yml -e @vars.yml
```

This configures:
- OS hardening (SSH, file permissions)
- node-setup (kernel modules, sysctl)
- containerd runtime
- Node Exporter (port 9100)
- Prometheus scrape config
- AlertManager

> **Note:** Update `ansible/inventory/hosts.ini` with current worker node IPs from `kubectl get nodes -o wide` and bastion IP from `terraform output bastion_public_ip`.

### 6. Install Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f monitoring/alertmanager-values.yaml \
  --set prometheus-node-exporter.service.port=9101 \
  --set prometheus-node-exporter.service.targetPort=9101
```

> **Note:** Node Exporter port is set to 9101 to avoid conflict with Ansible-installed node-exporter on port 9100.

### 7. Install Metrics Server (for HPA)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## Microservices

| Service | Language | Port | Docker Image |
|---------|----------|------|--------------|
| node-service | Node.js | 3000 | ash080/node-service:v1 |
| python-service | Python/Flask | 5000 | ash080/python-service:v1 |
| go-service | Go | 8080 | ash080/go-service:v1 |

## Horizontal Pod Autoscaler

All services are configured with HPA:
- Min replicas: 2
- Max replicas: 8
- CPU threshold: 60%
- Memory threshold: 70%

```bash
kubectl get hpa -n production
```

## Port Forwarding

| Tool | Command | URL |
|------|---------|-----|
| ArgoCD | `kubectl port-forward svc/argocd-server -n argocd 8080:443` | https://localhost:8080 |
| Grafana | `kubectl --namespace monitoring port-forward deployment/monitoring-grafana 3000` | http://localhost:3000 |
| Prometheus | `kubectl port-forward -n monitoring svc/prometheus-operated 9090` | http://localhost:9090 |
| AlertManager | `kubectl port-forward -n monitoring pod/alertmanager-monitoring-kube-prometheus-alertmanager-0 9093` | http://localhost:9093 |
| Python Service | `kubectl port-forward svc/python-app-production-python-service 5000:5000 -n production` | http://localhost:5000 |
| Node Service | `kubectl port-forward svc/node-app-production-node-service 3000:3000 -n production` | http://localhost:3000 |
| Go Service | `kubectl port-forward svc/go-app-production-go-service 8080:8080 -n production` | http://localhost:8080 |

## Monitoring Runbook

### Grafana Dashboards

- **Node Exporter Full** (ID: 1860) — CPU, memory, disk, network per node
- **Kubernetes / Views / Pods** (ID: 15760) — pod CPU/memory, restarts
- **Per-Service Health** (custom) — request rate, error rate, CPU, memory, restarts

### Alert Rules

| Alert | Condition | Severity |
|-------|-----------|----------|
| PodCrashLooping | Pod restarts > 3 in 5 minutes | Critical |
| HighCPUUsage | CPU > 80% for 5 minutes | Warning |

### Common Issues

**Pods not starting:**
```bash
kubectl describe pod <pod-name> -n production
kubectl logs <pod-name> -n production
```

**ArgoCD out of sync:**
```bash
kubectl get applications -n argocd
argocd app sync <app-name>
```

**HPA showing unknown metrics:**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Terraform destroy fails (DependencyViolation):**
```bash
kubectl delete svc --all --all-namespaces
# Wait 2 minutes, then:
terraform destroy -auto-approve
```

**Node Exporter CrashLoopBackOff:**
Port 9100 already in use by Ansible-installed node-exporter. Use:
```bash
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f monitoring/alertmanager-values.yaml \
  --set prometheus-node-exporter.service.port=9101 \
  --set prometheus-node-exporter.service.targetPort=9101
```

## Teardown

```bash
# 1. Delete K8s services to remove AWS load balancers
kubectl delete svc --all --all-namespaces

# 2. Wait 2 minutes, then destroy infrastructure
cd k8s-terraform
terraform destroy -auto-approve
```
