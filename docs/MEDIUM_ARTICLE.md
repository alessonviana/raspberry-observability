# Building a Complete Observability Stack on Raspberry Pi with Kubernetes

*A comprehensive guide to deploying Grafana, Prometheus, Loki, and Tempo on a Raspberry Pi cluster using K3s, MetalLB, and Cloudflare Tunnel*

---

## Introduction

In the world of modern software development, observability has become a cornerstone of building reliable and maintainable systems. The ability to understand what's happening inside your applications through metrics, logs, and traces is no longer a luxury—it's a necessity.

But what if you could build a production-grade observability stack without spending thousands on cloud infrastructure? What if you could run the same tools that power Fortune 500 companies on a cluster of credit-card-sized computers sitting on your desk?

This article will guide you through building a complete observability platform on Raspberry Pi, using the same technologies trusted by organizations worldwide. By the end, you'll have a fully functional monitoring system that you can access from anywhere in the world—all running on hardware that costs less than a fancy dinner.

---

## Project Overview

### What We're Building

This project deploys a complete observability stack consisting of:

| Component | Purpose |
|-----------|---------|
| **Grafana** | Visualization and dashboarding |
| **Prometheus** | Metrics collection and alerting |
| **Loki** | Log aggregation and querying |
| **Tempo** | Distributed tracing |
| **Alloy** | OpenTelemetry collector |
| **MetalLB** | Bare-metal load balancer |
| **Cloudflare Tunnel** | Secure external access |

All of this runs on a Kubernetes cluster powered by K3s, a lightweight Kubernetes distribution perfect for resource-constrained environments.

### Why This Matters

Whether you're:
- A developer wanting to learn Kubernetes and observability
- A homelab enthusiast monitoring your self-hosted services
- A small team needing a cost-effective monitoring solution
- Someone preparing for cloud certifications with hands-on practice

This stack provides real-world experience with enterprise-grade tools at a fraction of the cost.

---

## The LGTM Stack: Why Grafana's Observability Suite?

### What is LGTM?

LGTM stands for **Loki, Grafana, Tempo, and Mimir** (or Prometheus)—a complete observability stack developed by Grafana Labs. In our implementation, we use Prometheus instead of Mimir for metrics storage, making our stack technically "LGTP," but the principles remain the same.

### The Three Pillars of Observability

Modern observability is built on three pillars, and our stack covers all of them:

**1. Metrics (Prometheus)**

Metrics are numerical measurements collected over time. They answer questions like:
- How much CPU is my application using?
- What's my request latency at the 99th percentile?
- How many errors occurred in the last hour?

Prometheus excels at collecting, storing, and querying time-series metrics. Its pull-based model and powerful PromQL query language make it the de facto standard for Kubernetes monitoring.

**2. Logs (Loki)**

Logs are timestamped records of discrete events. They tell you:
- What error messages are my applications generating?
- What happened before the system crashed?
- Who accessed what resource and when?

Loki is designed to be cost-effective and easy to operate. Unlike traditional log aggregation systems, Loki indexes only metadata (labels) rather than the full text of logs, making it incredibly efficient for storage and queries.

**3. Traces (Tempo)**

Traces follow a request as it travels through your distributed system. They reveal:
- Which service is causing the bottleneck?
- What's the complete path of a failed request?
- How do microservices interact with each other?

Tempo provides distributed tracing without requiring a complex sampling configuration. It integrates seamlessly with Grafana, allowing you to jump from a metric to related logs and traces with a single click.

### Why Not Just Use Prometheus?

While Prometheus alone is powerful for metrics, modern applications require a holistic view:

```
User Request → API Gateway → Auth Service → Database → Cache → Response
      ↓            ↓             ↓            ↓         ↓
   [Traces capture the complete journey]
   [Logs capture what each service said]
   [Metrics capture how each service performed]
```

The magic happens when these three data types are correlated in Grafana. You can:
1. See a spike in error rate (metric)
2. Click to view related error logs (logs)
3. Click to see the trace of a failed request (traces)

This correlation dramatically reduces mean time to resolution (MTTR) when debugging issues.

### Grafana: The Unified Interface

Grafana ties everything together with:
- Beautiful, customizable dashboards
- Alerting across all data sources
- Exploration tools for ad-hoc queries
- Team collaboration features
- Extensive plugin ecosystem

---

## Why MetalLB? Solving the LoadBalancer Problem

### The Challenge

When you create a Kubernetes Service with `type: LoadBalancer` in a cloud environment (AWS, GCP, Azure), the cloud provider automatically provisions an external IP address. Your service becomes accessible from the internet within minutes.

But what happens when you're running Kubernetes on bare metal—like a Raspberry Pi cluster in your home? There's no cloud provider to provision that IP address. Your service stays in "Pending" state forever:

```bash
$ kubectl get svc my-service
NAME         TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)
my-service   LoadBalancer   10.43.100.50   <pending>     80:31234/TCP
```

### The Solution: MetalLB

MetalLB is a load balancer implementation for bare-metal Kubernetes clusters. It provides a network load balancer that integrates with standard network equipment.

In Layer 2 mode (which we use), MetalLB responds to ARP requests on your local network, making your Kubernetes services accessible via IP addresses on your home network:

```bash
$ kubectl get svc my-service
NAME         TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)
my-service   LoadBalancer   10.43.100.50   192.168.1.201   80:31234/TCP
```

Now any device on your network can access the service at `192.168.1.201`.

### How It Works

```
┌──────────────────────────────────────────────────────────────┐
│                     Your Home Network                        │
│                      192.168.1.0/24                          │
│                                                              │
│   ┌─────────┐         ┌─────────────────────────────────┐   │
│   │ Laptop  │         │     Raspberry Pi K3s Cluster    │   │
│   │         │         │                                 │   │
│   │         │  ARP    │  ┌─────────┐    ┌───────────┐  │   │
│   │         │◄───────►│  │ MetalLB │    │  Grafana  │  │   │
│   │         │         │  │ Speaker │───►│   Pod     │  │   │
│   │         │         │  └─────────┘    └───────────┘  │   │
│   └─────────┘         │                                 │   │
│                       │  Assigned IP: 192.168.1.201     │   │
│                       └─────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

MetalLB:
1. Watches for Services with `type: LoadBalancer`
2. Assigns an IP from your configured pool
3. Announces that IP on your network via ARP
4. Routes traffic to the appropriate pods

---

## Why Cloudflare Tunnel? Secure Access from Anywhere

### The Problem with Traditional Exposure

Traditionally, exposing a home service to the internet required:
- Port forwarding on your router
- Dynamic DNS to handle changing IP addresses
- SSL certificates for HTTPS
- Firewall configuration
- Dealing with CGNAT (if your ISP uses it)

Each of these introduces complexity and security risks. An open port is an attack vector.

### Cloudflare Tunnel: Zero Trust Access

Cloudflare Tunnel (formerly Argo Tunnel) flips the model on its head. Instead of opening ports inbound, your cluster creates an outbound connection to Cloudflare's edge network:

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                │
│                                                                 │
│    ┌────────────┐         ┌─────────────────────────────┐      │
│    │   User     │         │   Cloudflare Edge Network   │      │
│    │  Browser   │────────►│                             │      │
│    │            │  HTTPS  │   grafana.yourdomain.com    │      │
│    └────────────┘         └──────────────┬──────────────┘      │
│                                          │                      │
└──────────────────────────────────────────│──────────────────────┘
                                           │
                    ┌──────────────────────│──────────────────────┐
                    │  YOUR HOME NETWORK   │  (No open ports!)    │
                    │                      ▼                      │
                    │            ┌──────────────────┐             │
                    │            │  cloudflared     │             │
                    │            │  (outbound only) │             │
                    │            └────────┬─────────┘             │
                    │                     │                       │
                    │                     ▼                       │
                    │            ┌──────────────────┐             │
                    │            │     Grafana      │             │
                    │            │   192.168.1.201  │             │
                    │            └──────────────────┘             │
                    └─────────────────────────────────────────────┘
```

### Benefits

1. **No Open Ports**: Your firewall stays completely closed
2. **Built-in SSL**: Cloudflare handles HTTPS automatically
3. **DDoS Protection**: Cloudflare's network absorbs attacks
4. **Access Control**: Add authentication at Cloudflare's edge
5. **Works Behind CGNAT**: No issues with carrier-grade NAT
6. **Simple Setup**: Just a token, no complex configuration

---

## Hardware: The Raspberry Pi Cluster

### My Setup

This project runs on a Raspberry Pi cluster consisting of:

| Role | Hardware | Specs |
|------|----------|-------|
| Control Plane | Raspberry Pi 4 Model B | 8GB RAM, 128GB SD |
| Worker Node 1 | Raspberry Pi 4 Model B | 4GB RAM, 64GB SD |
| Worker Node 2 | Raspberry Pi 4 Model B | 4GB RAM, 64GB SD |

**Additional Equipment:**
- Gigabit Ethernet switch
- USB-C power supplies (5V 3A each)
- A cluster case or rack for organization
- Ethernet cables

### Why Raspberry Pi?

- **Cost-effective**: ~$200-300 for a complete cluster
- **Low power**: ~15W total consumption
- **Silent**: No fans (with proper cooling)
- **ARM64**: Same architecture as cloud instances
- **Educational**: Learn real Kubernetes, not simulations

### Resource Considerations

Running a full observability stack on limited resources requires optimization. Our Helm chart is tuned for Raspberry Pi with:

- Reduced replica counts
- Conservative memory limits
- Filesystem-based storage (not object storage)
- 60-second scrape intervals (vs. 15s default)

The complete stack uses approximately:
- **CPU**: 2-3 cores sustained
- **Memory**: 4-6GB across the cluster
- **Storage**: 50-60GB for a week of retention

---

## Prerequisites

Before deploying, ensure you have:

### 1. Kubernetes Cluster

A running K3s cluster is recommended. Install with:

```bash
# On the master node
curl -sfL https://get.k3s.io | sh -

# Get the token for worker nodes
sudo cat /var/lib/rancher/k3s/server/node-token

# On worker nodes
curl -sfL https://get.k3s.io | K3S_URL=https://<master-ip>:6443 \
  K3S_TOKEN=<token> sh -
```

### 2. kubectl Configured

```bash
# Copy kubeconfig from master
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# Verify connection
kubectl get nodes
```

### 3. Helm 3.x Installed

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
```

### 4. Network Information

You'll need:
- Your local network CIDR (e.g., `192.168.1.0/24`)
- An available IP range for MetalLB (e.g., `192.168.1.200-192.168.1.220`)

To find your network:
```bash
ip route | grep default
# Example output: default via 192.168.1.1 dev eth0
# Your network is likely 192.168.1.0/24
```

### 5. (Optional) Cloudflare Account

For external access:
1. A domain managed by Cloudflare
2. A Cloudflare Tunnel token from the Zero Trust dashboard

---

## Deployment Guide

### Step 1: Clone the Repository

```bash
git clone https://github.com/alessonviana/raspberry-observability.git
cd raspberry-observability
```

### Step 2: Review Configuration (Optional)

The default configuration works for most setups, but you can customize:

```bash
# Edit values if needed
vim helm-chart/observability/values.yaml
```

Key settings to consider:
- `grafana.adminPassword`: Change the default password
- Storage sizes for your retention needs
- Resource limits if you have more/less capacity

### Step 3: Deploy the Stack

Run the automated deployment script:

```bash
./deploy.sh \
  --network 192.168.1.0/24 \
  --ip-range 192.168.1.200-192.168.1.220
```

The script will:
1. Validate your inputs
2. Add required Helm repositories
3. Deploy MetalLB in `metallb-system` namespace
4. Configure the IP address pool
5. Deploy the monitoring stack in `monitoring` namespace
6. Configure LoadBalancer services with static IPs

**With Cloudflare Tunnel:**

```bash
./deploy.sh \
  --network 192.168.1.0/24 \
  --ip-range 192.168.1.200-192.168.1.220 \
  --cloudflare-token "your-tunnel-token-here"
```

### Step 4: Verify Deployment

```bash
# Check MetalLB
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system

# Check monitoring stack
kubectl get pods -n monitoring

# Check LoadBalancer services
kubectl get svc -n monitoring | grep LoadBalancer
```

Expected output:
```
NAME                                    TYPE           EXTERNAL-IP
monitoring-grafana                      LoadBalancer   192.168.1.201
monitoring-kube-prometheus-prometheus   LoadBalancer   192.168.1.202
monitoring-kube-prometheus-alertmanager LoadBalancer   192.168.1.203
```

### Step 5: Access Your Services

**Grafana** (Dashboards):
```
URL: http://192.168.1.201
Username: admin
Password: (retrieve with command below)
```

```bash
kubectl get secret monitoring-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

**Prometheus** (Metrics):
```
URL: http://192.168.1.202:9090
```

**Alertmanager** (Alerts):
```
URL: http://192.168.1.203:9093
```

---

## What's Next?

Once your stack is running, you can:

### 1. Explore Pre-built Dashboards

Grafana comes with dashboards for:
- Kubernetes cluster monitoring
- Node metrics (CPU, memory, disk, network)
- Pod and container statistics

### 2. Add Your Applications

Configure your applications to send:
- Metrics to Prometheus (via ServiceMonitor CRDs)
- Logs to Loki (via Alloy)
- Traces to Tempo (via OTLP)

### 3. Set Up Alerts

Create alert rules in Prometheus for:
- High CPU/memory usage
- Pod restart loops
- Disk space warnings

### 4. Configure Cloudflare Access

If using Cloudflare Tunnel:
1. Go to Cloudflare Zero Trust dashboard
2. Add a public hostname for your tunnel
3. Point it to your Grafana service

---

## Troubleshooting

### Pods Stuck in Pending

Usually a resource issue:
```bash
kubectl describe pod <pod-name> -n monitoring
```

### MetalLB Not Assigning IPs

Check the speaker pods and IP pool:
```bash
kubectl logs -n metallb-system -l app.kubernetes.io/name=metallb
kubectl get ipaddresspool -n metallb-system -o yaml
```

### High Memory Usage

Reduce retention periods in `values.yaml`:
```yaml
prometheus:
  prometheus:
    retention: "3d"  # Reduce from 7d
```

### Services Not Accessible

Verify your IP range doesn't conflict with existing devices:
```bash
# Scan your network
nmap -sn 192.168.1.200-220
```

---

## Conclusion

You now have a production-grade observability stack running on Raspberry Pi—the same tools used by companies like Google, Amazon, and Netflix, running on hardware that fits in your palm.

This setup provides:
- **Metrics** with Prometheus for performance monitoring
- **Logs** with Loki for debugging and auditing
- **Traces** with Tempo for distributed system analysis
- **Visualization** with Grafana for beautiful dashboards
- **External access** with Cloudflare Tunnel for anywhere monitoring
- **Load balancing** with MetalLB for service exposure

The total cost? Less than a month of cloud monitoring services.

Whether you're learning Kubernetes, building a homelab, or creating a cost-effective monitoring solution for a small team, this stack proves that enterprise-grade observability doesn't require enterprise-grade budgets.

---

## Resources

- **GitHub Repository**: [github.com/alessonviana/raspberry-observability](https://github.com/alessonviana/raspberry-observability)
- **Grafana Documentation**: [grafana.com/docs](https://grafana.com/docs)
- **Prometheus Documentation**: [prometheus.io/docs](https://prometheus.io/docs)
- **MetalLB Documentation**: [metallb.universe.tf](https://metallb.universe.tf)
- **Cloudflare Tunnel**: [developers.cloudflare.com/cloudflare-one/connections/connect-apps](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps)

---

*If you found this article helpful, please give it a clap and follow for more cloud-native content. Feel free to reach out with questions or share your own Raspberry Pi cluster setup!*

---

**Tags**: #Kubernetes #RaspberryPi #Observability #Grafana #Prometheus #DevOps #HomeLab #CloudNative #Monitoring
