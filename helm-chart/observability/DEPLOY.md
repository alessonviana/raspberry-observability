# Quick Deployment Guide

## Step-by-Step Deployment

### 1. Prerequisites

Make sure you have:
- Kubernetes cluster running
- Helm 3.x installed
- kubectl configured

### 2. Add Helm Repositories

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add metallb https://metallb.github.io/metallb
helm repo update
```

### 3. Navigate to Chart Directory

```bash
cd helm-chart/observability
```

### 4. Update Dependencies

```bash
helm dependency update
```

This will download all required charts (Grafana, Prometheus, Loki, Tempo, Alloy).

### 5. (Optional) Customize Values

Edit the `values.yaml` file if needed:

```bash
# Important: Change the default Grafana password
vim values.yaml
```

Search for `adminPassword` and change from `"ChangeMe-StrongPassword"` to a secure password.

### 6. Install the Chart

```bash
helm install observability . \
  --namespace observability \
  --create-namespace \
  --wait
```

The `--wait` flag waits for all resources to be ready.

### 7. Verify Installation

```bash
# View pods
kubectl get pods -n observability

# View services
kubectl get svc -n observability

# View PVCs (persistent volumes)
kubectl get pvc -n observability
```

### 8. Access Grafana

#### Get admin password:

```bash
kubectl get secret --namespace observability observability-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

#### Port-forward for local access:

```bash
kubectl port-forward --namespace observability svc/observability-grafana 3000:80
```

Access: http://localhost:3000
- Username: `admin`
- Password: (obtained from the command above)

### 9. Access Prometheus

```bash
kubectl port-forward --namespace observability svc/observability-kube-prometheus-stack-prometheus 9090:9090
```

Access: http://localhost:9090

## Useful Commands

### View logs for a component:

```bash
# Grafana
kubectl logs -n observability -l app.kubernetes.io/name=grafana

# Prometheus
kubectl logs -n observability -l app.kubernetes.io/name=prometheus

# Loki
kubectl logs -n observability -l app.kubernetes.io/name=loki

# Tempo
kubectl logs -n observability -l app.kubernetes.io/name=tempo

# Alloy
kubectl logs -n observability -l app.kubernetes.io/name=alloy
```

### Update the Chart

```bash
cd helm-chart/observability
helm dependency update
helm upgrade observability . \
  --namespace observability \
  --wait
```

### Uninstall

```bash
helm uninstall observability --namespace observability
```

**Warning**: Persistent Volumes are not automatically removed. To remove them:

```bash
kubectl delete pvc --all -n observability
```

## Troubleshooting

### Pods not starting

```bash
# View detailed status
kubectl describe pod <pod-name> -n observability

# View namespace events
kubectl get events -n observability --sort-by='.lastTimestamp'
```

### Resource issues

If pods are being evicted, reduce resource limits in `values.yaml`.

### Storage issues

```bash
# View PVCs
kubectl get pvc -n observability

# View PVC details
kubectl describe pvc <pvc-name> -n observability
```

## Service Structure

After deployment, the following services will be available in the `observability` namespace:

- `observability-grafana` (port 80)
- `observability-kube-prometheus-stack-prometheus` (port 9090)
- `observability-kube-prometheus-stack-alertmanager` (port 9093)
- `loki` (port 3100)
- `tempo` (ports 3100, 4317, 4318)
- `alloy` (ports 4317, 4318)

All services are configured for internal communication via Kubernetes DNS.

## MetalLB Configuration

MetalLB is automatically deployed and configured to provide LoadBalancer services on your local network.

### Network Configuration

- **Local Network**: 192.168.2.0/24
- **IP Range**: 192.168.2.100 - 192.168.2.250
- **Controller IP**: 192.168.2.110
- **Namespace**: `metallb`

### How It Works

MetalLB assigns IP addresses from the configured range to services with `type: LoadBalancer`. This allows services to be accessible from your local network without needing a cloud provider's load balancer.

### Verify MetalLB

After deployment, check MetalLB status:

```bash
# Check MetalLB pods
kubectl get pods -n metallb

# Check IPAddressPool
kubectl get ipaddresspool -n metallb

# Check L2Advertisement
kubectl get l2advertisement -n metallb
```

### Using LoadBalancer Services

To expose a service via MetalLB, set its type to `LoadBalancer`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: LoadBalancer
  ports:
  - port: 80
```

MetalLB will automatically assign an IP from the configured range (192.168.2.100-250).

## Cloudflare Tunnel Setup (Optional)

To expose services externally via Cloudflare Tunnel:

### 1. Get Cloudflare Tunnel Token

1. Go to https://one.dash.cloudflare.com/
2. Navigate to **Networks** → **Tunnels**
3. Create a new tunnel or select an existing one
4. Copy the tunnel token (it looks like: `eyJhIjoi...`)

### 2. Configure Tunnel in values.yaml

Edit `values.yaml`:

```yaml
cloudflared:
  enabled: true
  token: "your-cloudflare-tunnel-token-here"
```

### 3. Configure Routes in Cloudflare Dashboard

In the Cloudflare dashboard, configure public hostnames for your services:

- **Grafana**: `grafana.yourdomain.com` → `http://observability-grafana.observability.svc.cluster.local:80`
- **Prometheus** (optional): `prometheus.yourdomain.com` → `http://observability-kube-prometheus-stack-prometheus.observability.svc.cluster.local:9090`
- **Alertmanager** (optional): `alertmanager.yourdomain.com` → `http://observability-kube-prometheus-stack-alertmanager.observability.svc.cluster.local:9093`

### 4. Deploy or Update

```bash
# If deploying for the first time
helm install observability . \
  --namespace observability \
  --create-namespace \
  --wait

# If updating existing deployment
helm upgrade observability . \
  --namespace observability \
  --wait
```

### 5. Verify Tunnel

Check if the tunnel is running:

```bash
kubectl get pods -n observability -l app=cloudflared
kubectl logs -n observability -l app=cloudflared
```

### 6. Access Services

Once configured, you can access your services via the public hostnames configured in Cloudflare:
- Grafana: `https://grafana.yourdomain.com`
- Prometheus: `https://prometheus.yourdomain.com` (if enabled)
- Alertmanager: `https://alertmanager.yourdomain.com` (if enabled)

**Note**: The tunnel token contains all routing configuration. Routes are managed in the Cloudflare dashboard, not in the Helm chart.

### Cloudflare Tunnel Namespace

The Cloudflare Tunnel is deployed in the `cloudflare` namespace (separate from the `observability` namespace) for better organization.

Check tunnel status:

```bash
kubectl get pods -n cloudflare
kubectl logs -n cloudflare -l app=cloudflared
```
