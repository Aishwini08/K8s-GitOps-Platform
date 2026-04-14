# K8s GitOps Platform

A production-grade Kubernetes platform on AWS with GitOps, monitoring, and automated configuration management.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          AWS Cloud (ap-south-1)                  │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    VPC (10.0.0.0/16)                     │    │
│  │                                                           │    │
│  │  ┌──────────────────┐    ┌──────────────────┐           │    │
│  │  │  Public Subnet 1  │    │  Public Subnet 2  │           │    │
│  │  │  (10.0.1.0/24)   │    │  (10.0.2.0/24)   │           │    │
│  │  │  - Bastion Host  │    │  - NAT Gateway    │           │    │
│  │  └──────────────────┘    └──────────────────┘           │    │
│  │                                                           │    │
│  │  ┌──────────────────┐    ┌──────────────────┐           │    │
│  │  │  Private Subnet 1 │    │  Private Subnet 2 │           │    │
│  │  │  (10.0.3.0/24)   │    │  (10.0.4.0/24)   │           │    │
│  │  │  - EKS Worker 1  │    │  - EKS Worker 2   │           │    │
│  │  └──────────────────┘    └──────────────────┘           │    │
│  │                                                           │    │
│  │              ┌─────────────────────┐                     │    │
│  │              │   EKS Control Plane  │                     │    │
│  │              │   (my-eks-cluster)   │                     │    │
│  │              └─────────────────────┘                     │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

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
  AlertManager sends Slack
      notifications
```

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
│   │   ├── containerd/       # Container runtime setup
│   │   ├── node-exporter/    # Prometheus Node Exporter
│   │   └── alertmanager-config/  # AlertManager configuration
│   └── site.yml              # Master playbook
├── monitoring/
│   └── alertmanager-values.yaml  # Prometheus stack Helm values
└── k8s-terraform/
    ├── modules/
    │   ├── vpc/              # VPC, subnets, NAT, bastion
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
terraform apply
```

This creates:
- VPC with public/private subnets
- NAT Gateway
- Bastion host (for Ansible access)
- EKS cluster (v1.32) with 2 worker nodes (t3.medium)

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

Access ArgoCD UI at https://localhost:8080
- Username: `admin`
- Password: `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d`

### 4. Deploy Microservices via ArgoCD

> **Note:** ArgoCD watches the separate **[k8s-gitops-config](https://github.com/Aishwini08/k8s-gitops-config)** repository for Helm chart changes. The ArgoCD Application manifests in this repo point to that dedicated config repo.

```bash
kubectl apply -f argocd/apps/
kubectl get applications -n argocd
```

### 5. Configure Worker Nodes with Ansible

```bash
cd ansible
ansible-playbook -i inventory/hosts.ini site.yml -e @vars.yml
```

This configures:
- OS hardening (SSH, file permissions)
- containerd runtime
- Node Exporter (port 9100)
- AlertManager with Slack notifications

> **Note:** Ansible playbooks live in the separate **[k8s-ansible-config](https://github.com/Aishwini08/k8s-ansible-config)** repository.

### 6. Install Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f monitoring/alertmanager-values.yaml
```

Access Grafana at http://localhost:3000 (after port-forward):
```bash
kubectl --namespace monitoring port-forward deployment/monitoring-grafana 3000
```

## Microservices

| Service | Language | Port | Docker Image |
|---------|----------|------|--------------|
| node-service | Node.js | 3000 | ash080/node-service:v1 |
| python-service | Python/Flask | 5000 | ash080/python-service:v1 |
| go-service | Go | 8080 | ash080/go-service:v1 |

## Horizontal Pod Autoscaler

Python service is configured with HPA:
- Min replicas: 2
- Max replicas: 8
- CPU threshold: 60%
- Memory threshold: 70%

```bash
kubectl get hpa
```

## Monitoring Runbook

### Access Dashboards

| Tool | Command | URL |
|------|---------|-----|
| Grafana | `kubectl --namespace monitoring port-forward deployment/monitoring-grafana 3000` | http://localhost:3000 |
| Prometheus | `kubectl port-forward -n monitoring svc/prometheus-operated 9090` | http://localhost:9090 |
| AlertManager | `kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093` | http://localhost:9093 |
| ArgoCD | `kubectl port-forward svc/argocd-server -n argocd 8080:443` | https://localhost:8080 |

### Grafana Dashboards

- **Node Exporter Full** (ID: 1860) — CPU, memory, disk, network per node
- **Kubernetes Cluster** (ID: 15760) — pod CPU/memory, request rate, restarts

### Alert Rules

| Alert | Condition | Severity |
|-------|-----------|----------|
| PodCrashLooping | Pod restart rate > 0 for 5m | Critical |
| HighCPUUsage | CPU > 80% for 5m | Warning |

### Slack Notifications

AlertManager sends notifications to `#all-k8s-alerts` channel for:
- Pod crash looping
- High CPU usage
- Resolved alerts

### Common Issues

**Pods not starting:**
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

**ArgoCD out of sync:**
```bash
kubectl get applications -n argocd
# Force sync via ArgoCD UI or:
argocd app sync <app-name>
```

**Terraform destroy fails (DependencyViolation):**
```bash
# Delete Kubernetes LoadBalancer services first
kubectl delete svc --all
# Then destroy
terraform destroy
```

## Demo Video

[Watch Demo Video](https://www.youtube.com/watch?v=your-demo-video-link)

> **TODO:** Replace the link above with your actual demo video URL before submission.

## Teardown

```bash
# 1. Delete K8s services to remove AWS load balancers
kubectl delete svc --all

# 2. Destroy infrastructure
cd k8s-terraform
terraform destroy
```
