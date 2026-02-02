#!/bin/bash
#
# Observability Stack Deploy Script
# Deploys MetalLB, Monitoring Stack (Grafana, Prometheus, Loki, Tempo, Alloy), and Cloudflare Tunnel
#
# Usage: ./deploy.sh --network 192.168.1.0/24 --ip-range 192.168.1.200-192.168.1.220
#
# Author: Alesson Viana
# Repository: https://github.com/alessonviana/raspberry-observability
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/helm-chart/observability"
NETWORK=""
IP_RANGE=""
IP_START=""
IP_END=""
CLOUDFLARE_TOKEN=""
SKIP_METALLB=false
SKIP_MONITORING=false
SKIP_CLOUDFLARE=false
DRY_RUN=false

# Service IPs (will be calculated based on IP_START)
GRAFANA_IP=""
PROMETHEUS_IP=""
ALERTMANAGER_IP=""

#######################################
# Print colored message
#######################################
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

#######################################
# Print usage
#######################################
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy the complete observability stack on Kubernetes.

Required:
  --network CIDR          Network CIDR (e.g., 192.168.1.0/24)
  --ip-range RANGE        IP range for MetalLB (e.g., 192.168.1.200-192.168.1.220)

Optional:
  --cloudflare-token TOK  Cloudflare Tunnel token (or set CLOUDFLARE_TOKEN env var)
  --skip-metallb          Skip MetalLB installation
  --skip-monitoring       Skip monitoring stack installation
  --skip-cloudflare       Skip Cloudflare Tunnel installation
  --dry-run               Show what would be done without executing
  -h, --help              Show this help message

Examples:
  # Full deployment
  $0 --network 192.168.1.0/24 --ip-range 192.168.1.200-192.168.1.220

  # With Cloudflare Tunnel
  $0 --network 192.168.5.0/24 --ip-range 192.168.5.200-192.168.5.220 --cloudflare-token "eyJ..."

  # Skip MetalLB (already installed)
  $0 --network 192.168.1.0/24 --ip-range 192.168.1.200-192.168.1.220 --skip-metallb

EOF
    exit 1
}

#######################################
# Parse command line arguments
#######################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --network)
                NETWORK="$2"
                shift 2
                ;;
            --ip-range)
                IP_RANGE="$2"
                shift 2
                ;;
            --cloudflare-token)
                CLOUDFLARE_TOKEN="$2"
                shift 2
                ;;
            --skip-metallb)
                SKIP_METALLB=true
                shift
                ;;
            --skip-monitoring)
                SKIP_MONITORING=true
                shift
                ;;
            --skip-cloudflare)
                SKIP_CLOUDFLARE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Use env var for cloudflare token if not provided
    if [[ -z "$CLOUDFLARE_TOKEN" ]]; then
        CLOUDFLARE_TOKEN="${CLOUDFLARE_TOKEN:-}"
    fi
}

#######################################
# Validate inputs
#######################################
validate_inputs() {
    log_info "Validating inputs..."

    # Validate network CIDR
    if [[ -z "$NETWORK" ]]; then
        log_error "Network CIDR is required (--network)"
        usage
    fi

    if ! echo "$NETWORK" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$'; then
        log_error "Invalid network CIDR format: $NETWORK"
        log_error "Expected format: X.X.X.X/XX (e.g., 192.168.1.0/24)"
        exit 1
    fi

    # Validate IP range
    if [[ -z "$IP_RANGE" ]]; then
        log_error "IP range is required (--ip-range)"
        usage
    fi

    if ! echo "$IP_RANGE" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        log_error "Invalid IP range format: $IP_RANGE"
        log_error "Expected format: X.X.X.X-X.X.X.X (e.g., 192.168.1.200-192.168.1.220)"
        exit 1
    fi

    # Parse IP range
    IP_START=$(echo "$IP_RANGE" | cut -d'-' -f1)
    IP_END=$(echo "$IP_RANGE" | cut -d'-' -f2)

    # Calculate service IPs (start from IP_START + 1, as IP_START might be used by Traefik)
    local base_ip=$(echo "$IP_START" | cut -d'.' -f1-3)
    local start_last_octet=$(echo "$IP_START" | cut -d'.' -f4)

    GRAFANA_IP="${base_ip}.$((start_last_octet + 1))"
    PROMETHEUS_IP="${base_ip}.$((start_last_octet + 2))"
    ALERTMANAGER_IP="${base_ip}.$((start_last_octet + 3))"

    log_success "Inputs validated"
    log_info "  Network: $NETWORK"
    log_info "  IP Range: $IP_RANGE"
    log_info "  Grafana IP: $GRAFANA_IP"
    log_info "  Prometheus IP: $PROMETHEUS_IP"
    log_info "  Alertmanager IP: $ALERTMANAGER_IP"
}

#######################################
# Check prerequisites
#######################################
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi

    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed"
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    # Check chart directory
    if [[ ! -d "$CHART_DIR" ]]; then
        log_error "Chart directory not found: $CHART_DIR"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

#######################################
# Add Helm repositories
#######################################
add_helm_repos() {
    log_info "Adding Helm repositories..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would add Helm repositories"
        return
    fi

    helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo add metallb https://metallb.github.io/metallb 2>/dev/null || true
    helm repo update

    log_success "Helm repositories added"
}

#######################################
# Deploy MetalLB
#######################################
deploy_metallb() {
    if [[ "$SKIP_METALLB" == "true" ]]; then
        log_warn "Skipping MetalLB installation (--skip-metallb)"
        return
    fi

    log_info "Deploying MetalLB..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy MetalLB to metallb-system namespace"
        log_info "[DRY-RUN] Would configure IP range: $IP_RANGE"
        return
    fi

    # Create namespace
    kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -

    # Check if MetalLB is already installed
    if helm status metallb -n metallb-system &> /dev/null; then
        log_info "MetalLB already installed, upgrading..."
        helm upgrade metallb metallb/metallb --namespace metallb-system --wait --timeout 5m
    else
        log_info "Installing MetalLB..."
        # Clean up any existing CRDs ownership issues
        for crd in $(kubectl get crd -o name 2>/dev/null | grep metallb); do
            kubectl annotate $crd meta.helm.sh/release-name=metallb --overwrite 2>/dev/null || true
            kubectl annotate $crd meta.helm.sh/release-namespace=metallb-system --overwrite 2>/dev/null || true
        done

        helm install metallb metallb/metallb --namespace metallb-system --wait --timeout 5m
    fi

    # Wait for MetalLB to be ready
    log_info "Waiting for MetalLB pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=metallb -n metallb-system --timeout=120s

    # Apply IP configuration
    log_info "Configuring MetalLB IP pool..."
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - ${IP_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF

    log_success "MetalLB deployed successfully"
}

#######################################
# Deploy Monitoring Stack
#######################################
deploy_monitoring() {
    if [[ "$SKIP_MONITORING" == "true" ]]; then
        log_warn "Skipping monitoring stack installation (--skip-monitoring)"
        return
    fi

    log_info "Deploying monitoring stack..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy monitoring stack to monitoring namespace"
        return
    fi

    # Create namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

    # Update Helm dependencies
    log_info "Updating Helm dependencies..."
    cd "$CHART_DIR"
    helm dependency update

    # Create values override file
    local values_override="/tmp/values-override-$$.yaml"
    cat > "$values_override" <<EOF
# Auto-generated values override
metallb:
  enabled: false  # MetalLB is installed separately
  namespace: metallb-system
  network:
    subnet: "${NETWORK}"
    ipRange:
      start: "${IP_START}"
      end: "${IP_END}"

cloudflared:
  enabled: false  # Will be enabled separately if token provided
EOF

    # Check if monitoring release exists
    if helm status monitoring -n monitoring &> /dev/null; then
        log_info "Monitoring stack already installed, upgrading..."
        helm upgrade monitoring . \
            --namespace monitoring \
            --values "$values_override" \
            --wait \
            --timeout 15m
    else
        log_info "Installing monitoring stack..."
        helm install monitoring . \
            --namespace monitoring \
            --create-namespace \
            --values "$values_override" \
            --wait \
            --timeout 15m
    fi

    rm -f "$values_override"

    # Wait for pods to be ready
    log_info "Waiting for monitoring pods to be ready..."
    sleep 10
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s || true
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=300s || true

    log_success "Monitoring stack deployed successfully"
}

#######################################
# Configure LoadBalancer Services
#######################################
configure_loadbalancer_services() {
    if [[ "$SKIP_MONITORING" == "true" ]]; then
        log_warn "Skipping LoadBalancer configuration (monitoring not installed)"
        return
    fi

    log_info "Configuring LoadBalancer services with static IPs..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure:"
        log_info "[DRY-RUN]   - Grafana: $GRAFANA_IP"
        log_info "[DRY-RUN]   - Prometheus: $PROMETHEUS_IP"
        log_info "[DRY-RUN]   - Alertmanager: $ALERTMANAGER_IP"
        return
    fi

    # Wait for services to exist
    log_info "Waiting for services to be available..."
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if kubectl get svc monitoring-grafana -n monitoring &> /dev/null; then
            break
        fi
        sleep 5
        ((attempt++))
    done

    # Configure Grafana
    log_info "Configuring Grafana LoadBalancer (IP: $GRAFANA_IP)..."
    kubectl patch svc monitoring-grafana -n monitoring \
        -p "{\"spec\": {\"type\": \"LoadBalancer\", \"loadBalancerIP\": \"$GRAFANA_IP\"}}" || true

    # Configure Prometheus
    log_info "Configuring Prometheus LoadBalancer (IP: $PROMETHEUS_IP)..."
    kubectl patch svc monitoring-kube-prometheus-prometheus -n monitoring \
        -p "{\"spec\": {\"type\": \"LoadBalancer\", \"loadBalancerIP\": \"$PROMETHEUS_IP\"}}" || true

    # Configure Alertmanager
    log_info "Configuring Alertmanager LoadBalancer (IP: $ALERTMANAGER_IP)..."
    kubectl patch svc monitoring-kube-prometheus-alertmanager -n monitoring \
        -p "{\"spec\": {\"type\": \"LoadBalancer\", \"loadBalancerIP\": \"$ALERTMANAGER_IP\"}}" || true

    # Wait for IPs to be assigned
    log_info "Waiting for external IPs to be assigned..."
    sleep 5

    log_success "LoadBalancer services configured"
}

#######################################
# Deploy Cloudflare Tunnel
#######################################
deploy_cloudflare() {
    if [[ "$SKIP_CLOUDFLARE" == "true" ]]; then
        log_warn "Skipping Cloudflare Tunnel installation (--skip-cloudflare)"
        return
    fi

    if [[ -z "$CLOUDFLARE_TOKEN" ]]; then
        log_warn "Skipping Cloudflare Tunnel installation (no token provided)"
        log_info "To install later, run with --cloudflare-token or set CLOUDFLARE_TOKEN env var"
        return
    fi

    log_info "Deploying Cloudflare Tunnel..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy Cloudflare Tunnel to cloudflare namespace"
        return
    fi

    # Create namespace
    kubectl create namespace cloudflare --dry-run=client -o yaml | kubectl apply -f -

    # Create secret with token
    kubectl create secret generic cloudflare-tunnel-token \
        --from-literal=token="$CLOUDFLARE_TOKEN" \
        --namespace cloudflare \
        --dry-run=client -o yaml | kubectl apply -f -

    # Deploy cloudflared
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: cloudflare
  labels:
    app: cloudflared
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      containers:
      - name: cloudflared
        image: cloudflare/cloudflared:latest
        args:
        - tunnel
        - --no-autoupdate
        - run
        - --token
        - \$(TUNNEL_TOKEN)
        env:
        - name: TUNNEL_TOKEN
          valueFrom:
            secretKeyRef:
              name: cloudflare-tunnel-token
              key: token
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
EOF

    log_success "Cloudflare Tunnel deployed successfully"
}

#######################################
# Print summary
#######################################
print_summary() {
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}    Deployment Complete!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] No changes were made${NC}"
        echo ""
        return
    fi

    echo -e "${BLUE}Service Access URLs:${NC}"
    echo ""

    if [[ "$SKIP_MONITORING" != "true" ]]; then
        echo -e "  ${GREEN}Grafana:${NC}      http://${GRAFANA_IP}"
        echo -e "  ${GREEN}Prometheus:${NC}   http://${PROMETHEUS_IP}:9090"
        echo -e "  ${GREEN}Alertmanager:${NC} http://${ALERTMANAGER_IP}:9093"
        echo ""
        echo -e "${BLUE}Grafana Credentials:${NC}"
        echo -e "  Username: admin"
        echo -e "  Password: $(kubectl get secret monitoring-grafana -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo 'ChangeMe-StrongPassword')"
    fi

    echo ""
    echo -e "${BLUE}Namespaces Created:${NC}"
    [[ "$SKIP_METALLB" != "true" ]] && echo "  - metallb-system"
    [[ "$SKIP_MONITORING" != "true" ]] && echo "  - monitoring"
    [[ -n "$CLOUDFLARE_TOKEN" && "$SKIP_CLOUDFLARE" != "true" ]] && echo "  - cloudflare"

    echo ""
    echo -e "${BLUE}Verify Deployment:${NC}"
    echo "  kubectl get pods -n metallb-system"
    echo "  kubectl get pods -n monitoring"
    echo "  kubectl get svc -n monitoring | grep LoadBalancer"
    echo ""
}

#######################################
# Main
#######################################
main() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}  Raspberry Pi Observability Stack${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""

    parse_args "$@"
    validate_inputs
    check_prerequisites
    add_helm_repos
    deploy_metallb
    deploy_monitoring
    configure_loadbalancer_services
    deploy_cloudflare
    print_summary
}

main "$@"
