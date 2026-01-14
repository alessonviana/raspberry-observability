# Raspberry Pi Observability Stack

A complete observability stack for Kubernetes clusters running on Raspberry Pi, featuring Grafana, Prometheus, Loki, Tempo, and Alloy.

## Components

| Component | Description | Purpose |
|-----------|-------------|---------|
| **Grafana** | Visualization platform | Dashboards and alerts |
| **Prometheus** | Metrics database | Time-series metrics storage |
| **Loki** | Log aggregation | Centralized logging |
| **Tempo** | Distributed tracing | Request tracing |
| **Alloy** | OpenTelemetry collector | Log and trace collection |
| **MetalLB** | Load balancer | External IP assignment |
| **Cloudflare Tunnel** | Secure tunnel | External access (optional) |

## Quick Start

### Prerequisites

- Kubernetes cluster (K3s, K8s, etc.)
- Helm 3.x installed
- kubectl configured
- Network CIDR and IP range for MetalLB

### One-Command Deploy

```bash
# Clone the repository
git clone https://github.com/alessonviana/raspberry-observability.git
cd raspberry-observability

# Deploy the complete stack
./deploy.sh --network 192.168.1.0/24 --ip-range 192.168.1.200-192.168.1.220
```

### Deploy with Cloudflare Tunnel

```bash
./deploy.sh \
  --network 192.168.1.0/24 \
  --ip-range 192.168.1.200-192.168.1.220 \
  --cloudflare-token "your-cloudflare-tunnel-token"
```

## Deploy Script Options

```
Usage: ./deploy.sh [OPTIONS]

Required:
  --network CIDR          Network CIDR (e.g., 192.168.1.0/24)
  --ip-range RANGE        IP range for MetalLB (e.g., 192.168.1.200-192.168.1.220)

Optional:
  --cloudflare-token TOK  Cloudflare Tunnel token
  --skip-metallb          Skip MetalLB installation
  --skip-monitoring       Skip monitoring stack installation
  --skip-cloudflare       Skip Cloudflare Tunnel installation
  --dry-run               Show what would be done without executing
  -h, --help              Show help message
```

## After Deployment

### Access URLs

After deployment, the services will be available at:

| Service | URL | Port |
|---------|-----|------|
| Grafana | http://192.168.1.201 | 80 |
| Prometheus | http://192.168.1.202 | 9090 |
| Alertmanager | http://192.168.1.203 | 9093 |

*Note: IPs are based on your configured range (start + 1, +2, +3)*

### Get Grafana Password

```bash
kubectl get secret monitoring-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

### Verify Deployment

```bash
# Check all pods
kubectl get pods -n metallb-system
kubectl get pods -n monitoring
kubectl get pods -n cloudflare

# Check LoadBalancer services
kubectl get svc -n monitoring | grep LoadBalancer
```

## Uninstall

### Remove Everything

```bash
./uninstall.sh --all
```

### Remove Specific Components

```bash
# Remove only monitoring stack
./uninstall.sh --monitoring

# Remove only MetalLB
./uninstall.sh --metallb

# Remove only Cloudflare Tunnel
./uninstall.sh --cloudflare
```

## Architecture

```
                                    ┌─────────────────┐
                                    │    Grafana      │
                                    │  192.168.1.201  │
                                    └────────┬────────┘
                                             │
                 ┌───────────────────────────┼───────────────────────────┐
                 │                           │                           │
                 ▼                           ▼                           ▼
        ┌────────────────┐          ┌────────────────┐          ┌────────────────┐
        │   Prometheus   │          │      Loki      │          │     Tempo      │
        │ 192.168.1.202  │          │   (internal)   │          │   (internal)   │
        └────────────────┘          └────────────────┘          └────────────────┘
                 ▲                           ▲                           ▲
                 │                           │                           │
        ┌────────┴────────┐                  │                           │
        │                 │                  │                           │
   ┌─────────┐    ┌───────────┐             │                           │
   │  Node   │    │   Kube    │     ┌───────┴───────┐                   │
   │Exporter │    │  State    │     │     Alloy     │───────────────────┘
   └─────────┘    │  Metrics  │     │  (DaemonSet)  │
                  └───────────┘     └───────────────┘
```

## Namespaces

| Namespace | Components |
|-----------|------------|
| `metallb-system` | MetalLB controller and speakers |
| `monitoring` | Grafana, Prometheus, Loki, Tempo, Alloy |
| `cloudflare` | Cloudflare Tunnel (optional) |

## IP Allocation

When you specify `--ip-range 192.168.1.200-192.168.1.220`, the IPs are allocated as:

| IP | Service |
|----|---------|
| 192.168.1.200 | Reserved for Traefik/Ingress |
| 192.168.1.201 | Grafana |
| 192.168.1.202 | Prometheus |
| 192.168.1.203 | Alertmanager |
| 192.168.1.204-220 | Available for other services |

## Configuration

### Customize Values

Edit `helm-chart/observability/values.yaml` to customize:

- Grafana admin password
- Resource limits
- Storage sizes
- Retention periods
- Component enable/disable

### Storage Requirements

| Component | Default Size |
|-----------|-------------|
| Prometheus | 20Gi |
| Loki | 20Gi |
| Tempo | 10Gi |
| Grafana | 5Gi |
| Alertmanager | 2Gi |

## Troubleshooting

### Pods not starting

```bash
kubectl describe pod <pod-name> -n monitoring
kubectl logs <pod-name> -n monitoring
```

### MetalLB not assigning IPs

```bash
kubectl get ipaddresspool -n metallb-system
kubectl logs -n metallb-system -l app.kubernetes.io/name=metallb
```

### Service stuck in Pending

```bash
kubectl describe svc <service-name> -n monitoring
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - feel free to use in your homelab!

## Author

**Alesson Viana**

- GitHub: [@alessonviana](https://github.com/alessonviana)
