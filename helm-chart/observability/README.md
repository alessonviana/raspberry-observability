# Observability Stack Helm Chart

This Helm chart deploys a complete observability stack optimized for Raspberry Pi, including:
- **Grafana**: Visualization and dashboards
- **Prometheus**: Metrics collection and alerting
- **Loki**: Log aggregation
- **Tempo**: Distributed tracing
- **Alloy**: OpenTelemetry collector for logs and traces

## Prerequisites

- Kubernetes cluster (1.24+)
- Helm 3.x installed
- kubectl configured to access your cluster
- Sufficient resources (recommended: 2GB+ RAM, 4+ CPU cores)

## Installation Steps

### 1. Add Required Helm Repositories

Add the Helm repositories for all dependencies:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### 2. Install Chart Dependencies

Navigate to the chart directory and update dependencies:

```bash
cd helm-chart/observability
helm dependency update
```

This will download all required subcharts and create a `charts/` directory.

### 3. Review and Customize Values (Optional)

Review the `values.yaml` file and customize if needed:

```bash
# Edit values.yaml to customize:
# - Grafana admin password
# - Resource limits
# - Storage sizes
# - Retention periods
vim values.yaml
```

**Important**: Change the default Grafana admin password in `values.yaml`:
```yaml
grafana:
  adminPassword: "YourStrongPasswordHere"
```

### 4. Deploy the Chart

Deploy the observability stack to the `observability` namespace:

```bash
helm install observability . \
  --namespace observability \
  --create-namespace \
  --wait
```

Or if you prefer to see what will be deployed first:

```bash
# Dry-run to see what will be deployed
helm install observability . \
  --namespace observability \
  --create-namespace \
  --dry-run \
  --debug

# Then deploy for real
helm install observability . \
  --namespace observability \
  --create-namespace \
  --wait
```

The `--wait` flag will wait for all resources to be ready before completing.

### 5. Verify Installation

Check that all pods are running:

```bash
kubectl get pods -n observability
```

You should see pods for:
- Grafana
- Prometheus server and alertmanager
- Loki
- Tempo
- Alloy (as DaemonSet)

Check services:

```bash
kubectl get svc -n observability
```

### 6. Access Grafana

Get the Grafana admin password:

```bash
kubectl get secret --namespace observability observability-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

Port-forward to access Grafana locally:

```bash
kubectl port-forward --namespace observability svc/observability-grafana 3000:80
```

Then open http://localhost:3000 in your browser and login with:
- Username: `admin`
- Password: (from the command above)

### 7. Access Prometheus

Port-forward to access Prometheus:

```bash
kubectl port-forward --namespace observability svc/observability-kube-prometheus-stack-prometheus 9090:9090
```

Then open http://localhost:9090 in your browser.

## Upgrade

To upgrade the chart with new values:

```bash
cd helm-chart/observability
helm dependency update
helm upgrade observability . \
  --namespace observability \
  --wait
```

## Uninstall

To remove the observability stack:

```bash
helm uninstall observability --namespace observability
```

**Note**: This will remove all resources but persistent volumes will remain. To also delete persistent volumes, you'll need to manually delete the PVCs:

```bash
kubectl delete pvc --all -n observability
```

## Configuration

### Key Configuration Options

- **Namespace**: Default is `observability` (configurable in values.yaml)
- **Retention**: 7 days for Prometheus, Loki, and Tempo
- **Storage**: Filesystem-based storage (suitable for single-node setups)
- **Resources**: Optimized for Raspberry Pi with low resource limits

### Component-Specific Settings

#### Grafana
- Default datasources (Prometheus, Loki, Tempo) are pre-configured
- Admin credentials can be changed in values.yaml

#### Prometheus
- Scrape interval: 60s
- Retention: 7 days
- Includes kube-state-metrics and node-exporter

#### Loki
- Single binary mode (not distributed)
- Filesystem storage
- 7-day retention

#### Tempo
- Single replica mode
- Filesystem storage
- 7-day retention

#### Alloy
- Runs as DaemonSet to collect logs from all nodes
- Configured to forward logs to Loki and traces to Tempo

#### Cloudflare Tunnel
- Optional component to expose services externally
- Uses Cloudflare Tunnel token for authentication
- Configure routes in Cloudflare dashboard

### Enabling Cloudflare Tunnel

To enable external access via Cloudflare Tunnel:

1. **Get your Cloudflare Tunnel token:**
   - Go to https://one.dash.cloudflare.com/
   - Create or select a tunnel
   - Copy the tunnel token

2. **Configure in values.yaml:**
   ```yaml
   cloudflared:
     enabled: true
     token: "your-cloudflare-tunnel-token-here"
   ```

3. **Configure routes in Cloudflare Dashboard:**
   - Set up public hostnames pointing to your services
   - The tunnel will automatically route traffic to the configured services

4. **Deploy:**
   ```bash
   helm upgrade observability . --namespace observability
   ```

The tunnel will expose your services through Cloudflare's network, providing secure external access without opening ports on your firewall.

## Troubleshooting

### Pods not starting

Check pod status and logs:

```bash
kubectl get pods -n observability
kubectl describe pod <pod-name> -n observability
kubectl logs <pod-name> -n observability
```

### Storage issues

Check persistent volume claims:

```bash
kubectl get pvc -n observability
kubectl describe pvc <pvc-name> -n observability
```

### Resource constraints

If pods are being evicted or not starting due to resource constraints, reduce resource limits in `values.yaml`.

## Architecture

```
┌─────────┐     ┌──────────┐     ┌──────┐
│ Alloy   │────▶│  Loki    │────▶│Grafana│
│(Daemon) │     │          │     │      │
└─────────┘     └──────────┘     └──────┘
     │
     │ Traces
     ▼
┌─────────┐     ┌──────────┐
│ Tempo  │────▶│  Grafana │
│        │     │          │
└────────┘     └──────────┘

┌──────────────┐     ┌──────────┐
│ Prometheus   │────▶│  Grafana │
│              │     │          │
└──────────────┘     └──────────┘
```

## License

This chart is provided as-is for use in homelab and development environments.

