# Observability Stack Helm Chart

This Helm chart deploys a complete observability stack optimized for Raspberry Pi, including:
- **Grafana**: Visualization and dashboards
- **Prometheus**: Metrics collection and alerting
- **Loki**: Log aggregation
- **Tempo**: Distributed tracing
- **Alloy**: OpenTelemetry collector for logs and traces
- **MetalLB**: Load balancer for bare metal Kubernetes clusters
- **Cloudflare Tunnel**: Secure external access (optional)

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
helm repo add metallb https://metallb.github.io/metallb
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

Deploy the observability stack to the `monitoring` namespace:

```bash
helm install monitoring . \
  --namespace monitoring \
  --create-namespace \
  --wait
```

Or if you prefer to see what will be deployed first:

```bash
# Dry-run to see what will be deployed
helm install monitoring . \
  --namespace monitoring \
  --create-namespace \
  --dry-run \
  --debug

# Then deploy for real
helm install monitoring . \
  --namespace monitoring \
  --create-namespace \
  --wait
```

The `--wait` flag will wait for all resources to be ready before completing.

### 5. Verify Installation

Check that all pods are running:

```bash
kubectl get pods -n monitoring
```

You should see pods for:
- Grafana
- Prometheus server and alertmanager
- Loki
- Tempo
- Alloy (as DaemonSet)

Check services:

```bash
kubectl get svc -n monitoring
```

### 6. Access Grafana

Get the Grafana admin password:

```bash
kubectl get secret --namespace monitoring monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

Port-forward to access Grafana locally:

```bash
kubectl port-forward --namespace monitoring svc/monitoring-grafana 3000:80
```

Then open http://localhost:3000 in your browser and login with:
- Username: `admin`
- Password: (from the command above)

### 7. Access Prometheus

Port-forward to access Prometheus:

```bash
kubectl port-forward --namespace monitoring svc/monitoring-kube-prometheus-stack-prometheus 9090:9090
```

Then open http://localhost:9090 in your browser.

## Upgrade

To upgrade the chart with new values:

```bash
cd helm-chart/observability
helm dependency update
helm upgrade monitoring . \
  --namespace monitoring \
  --wait
```

## Uninstall

To remove the observability stack:

```bash
helm uninstall monitoring --namespace monitoring
```

**Note**: This will remove all resources but persistent volumes will remain. To also delete persistent volumes, you'll need to manually delete the PVCs:

```bash
kubectl delete pvc --all -n monitoring
```

## Configuration

### Key Configuration Options

- **Namespace**: Default is `monitoring` (configurable in values.yaml)
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
- Configured to forward logs to Loki, traces to Tempo e **métricas OTLP** ao Prometheus

#### Coletor OTLP (OpenTelemetry)
O Alloy atua como **coletor OTLP**: aplicações instrumentadas com OpenTelemetry podem enviar métricas e traces diretamente para o stack. O serviço do Alloy é exposto como **LoadBalancer** para acesso de sistemas **fora do cluster**.

**Endpoints externos (para configurar no OTEL do sistema monitorado):**
- **gRPC:** `<IP_DO_LOADBALANCER>:4317`
- **HTTP:** `http://<IP_DO_LOADBALANCER>:4318`

O IP do LoadBalancer é atribuído pelo MetalLB (faixa 192.168.2.100–192.168.2.250). Para descobrir o IP após o deploy:
```bash
kubectl get svc -n monitoring monitoring-alloy -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Para um **endpoint estável**, defina um IP fixo em `values.yaml` em `alloy.service.annotations` com `metallb.universe.tf/loadBalancerIP: "192.168.2.111"` (escolha um IP livre na sua rede).

**Exemplo de configuração no sistema monitorado (variáveis de ambiente):**
```bash
# gRPC (recomendado) — use host:port sem esquema
OTEL_EXPORTER_OTLP_ENDPOINT=<IP_LOADBALANCER>:4317

# ou HTTP
OTEL_EXPORTER_OTLP_ENDPOINT=http://<IP_LOADBALANCER>:4318
```

**Fluxo:** Métricas OTLP → Alloy → Prometheus → Grafana | Traces OTLP → Alloy → Tempo → Grafana

#### MetalLB
- Provides LoadBalancer services for bare metal Kubernetes
- Configured for local network: 192.168.2.0/24
- IP range: 192.168.2.100 - 192.168.2.250
- Deployed in `metallb` namespace
- Uses Layer 2 mode for simplicity

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
   helm upgrade monitoring . --namespace monitoring
   ```

The tunnel will expose your services through Cloudflare's network, providing secure external access without opening ports on your firewall.

## Troubleshooting

### Pods not starting

Check pod status and logs:

```bash
kubectl get pods -n monitoring
kubectl describe pod <pod-name> -n monitoring
kubectl logs <pod-name> -n monitoring
```

### Storage issues

Check persistent volume claims:

```bash
kubectl get pvc -n monitoring
kubectl describe pvc <pvc-name> -n monitoring
```

### Resource constraints

If pods are being evicted or not starting due to resource constraints, reduce resource limits in `values.yaml`.

## Architecture

```
                    ┌──────────────┐     ┌──────────┐
                    │ Prometheus   │────▶│  Grafana │
                    │              │     │          │
                    └──────▲───────┘     └──────────┘
                           │ remote write
         OTLP (gRPC/HTTP)  │
┌──────────────┐     ┌─────┴─────┐     ┌──────────┐
│ Sua aplicação│────▶│   Alloy   │────▶│  Loki    │────▶ Grafana
│ (OpenTelemetry)     │ (Daemon)  │     │          │
└──────────────┘     └─────┬─────┘     └──────────┘
                           │ Traces
                           ▼
                    ┌─────────┐     ┌──────────┐
                    │ Tempo    │────▶│  Grafana │
                    └─────────┘     └──────────┘
```

## License

This chart is provided as-is for use in homelab and development environments.

