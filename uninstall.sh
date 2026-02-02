#!/bin/bash
#
# Observability Stack Uninstall Script
# Removes MetalLB, Monitoring Stack, and Cloudflare Tunnel
#
# Usage: ./uninstall.sh [--all | --metallb | --monitoring | --cloudflare]
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

# Flags
UNINSTALL_ALL=false
UNINSTALL_METALLB=false
UNINSTALL_MONITORING=false
UNINSTALL_CLOUDFLARE=false
FORCE=false

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

Uninstall the observability stack from Kubernetes.

Options:
  --all           Uninstall all components (MetalLB, Monitoring, Cloudflare)
  --metallb       Uninstall only MetalLB
  --monitoring    Uninstall only Monitoring stack
  --cloudflare    Uninstall only Cloudflare Tunnel
  --force         Force deletion without confirmation
  -h, --help      Show this help message

Examples:
  # Uninstall everything
  $0 --all

  # Uninstall only monitoring stack
  $0 --monitoring

  # Force uninstall without confirmation
  $0 --all --force

EOF
    exit 1
}

#######################################
# Parse command line arguments
#######################################
parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                UNINSTALL_ALL=true
                shift
                ;;
            --metallb)
                UNINSTALL_METALLB=true
                shift
                ;;
            --monitoring)
                UNINSTALL_MONITORING=true
                shift
                ;;
            --cloudflare)
                UNINSTALL_CLOUDFLARE=true
                shift
                ;;
            --force)
                FORCE=true
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

    if [[ "$UNINSTALL_ALL" == "true" ]]; then
        UNINSTALL_METALLB=true
        UNINSTALL_MONITORING=true
        UNINSTALL_CLOUDFLARE=true
    fi
}

#######################################
# Confirm action
#######################################
confirm() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    echo ""
    echo -e "${YELLOW}WARNING: This will delete the following components:${NC}"
    [[ "$UNINSTALL_MONITORING" == "true" ]] && echo "  - Monitoring stack (Grafana, Prometheus, Loki, Tempo, Alloy)"
    [[ "$UNINSTALL_METALLB" == "true" ]] && echo "  - MetalLB"
    [[ "$UNINSTALL_CLOUDFLARE" == "true" ]] && echo "  - Cloudflare Tunnel"
    echo ""
    echo -e "${YELLOW}This action cannot be undone. All data will be lost.${NC}"
    echo ""

    read -p "Are you sure you want to continue? (yes/no): " response
    if [[ "$response" != "yes" ]]; then
        log_info "Uninstall cancelled"
        exit 0
    fi
}

#######################################
# Uninstall Cloudflare Tunnel
#######################################
uninstall_cloudflare() {
    if [[ "$UNINSTALL_CLOUDFLARE" != "true" ]]; then
        return
    fi

    log_info "Uninstalling Cloudflare Tunnel..."

    # Delete deployment and secret
    kubectl delete deployment cloudflared -n cloudflare 2>/dev/null || true
    kubectl delete secret cloudflare-tunnel-token -n cloudflare 2>/dev/null || true

    # Delete namespace
    if kubectl get namespace cloudflare &> /dev/null; then
        kubectl delete namespace cloudflare --wait=true --timeout=60s 2>/dev/null || true
    fi

    log_success "Cloudflare Tunnel uninstalled"
}

#######################################
# Uninstall Monitoring Stack
#######################################
uninstall_monitoring() {
    if [[ "$UNINSTALL_MONITORING" != "true" ]]; then
        return
    fi

    log_info "Uninstalling Monitoring stack..."

    # Uninstall Helm release
    if helm status monitoring -n monitoring &> /dev/null; then
        helm uninstall monitoring -n monitoring --wait --timeout 5m || true
    fi

    # Delete remaining resources
    log_info "Cleaning up remaining resources..."
    kubectl delete all --all -n monitoring 2>/dev/null || true
    kubectl delete secrets --all -n monitoring 2>/dev/null || true
    kubectl delete configmaps --all -n monitoring 2>/dev/null || true
    kubectl delete pvc --all -n monitoring 2>/dev/null || true
    kubectl delete serviceaccounts --all -n monitoring 2>/dev/null || true

    # Delete cluster-scoped resources
    log_info "Cleaning up cluster-scoped resources..."
    kubectl get clusterrole -o name 2>/dev/null | grep -E "monitoring|prometheus|grafana|loki|tempo|alloy" | xargs kubectl delete 2>/dev/null || true
    kubectl get clusterrolebinding -o name 2>/dev/null | grep -E "monitoring|prometheus|grafana|loki|tempo|alloy" | xargs kubectl delete 2>/dev/null || true

    # Delete namespace
    if kubectl get namespace monitoring &> /dev/null; then
        log_info "Deleting monitoring namespace..."
        kubectl delete namespace monitoring --wait=true --timeout=120s 2>/dev/null || true

        # Force delete if stuck
        if kubectl get namespace monitoring &> /dev/null; then
            log_warn "Namespace stuck, forcing deletion..."
            kubectl get namespace monitoring -o json | \
                jq '.spec.finalizers = []' | \
                kubectl replace --raw "/api/v1/namespaces/monitoring/finalize" -f - 2>/dev/null || true
        fi
    fi

    log_success "Monitoring stack uninstalled"
}

#######################################
# Uninstall MetalLB
#######################################
uninstall_metallb() {
    if [[ "$UNINSTALL_METALLB" != "true" ]]; then
        return
    fi

    log_info "Uninstalling MetalLB..."

    # Delete configuration
    kubectl delete ipaddresspool --all -n metallb-system 2>/dev/null || true
    kubectl delete l2advertisement --all -n metallb-system 2>/dev/null || true

    # Uninstall Helm release
    if helm status metallb -n metallb-system &> /dev/null; then
        helm uninstall metallb -n metallb-system --wait --timeout 5m || true
    fi

    # Delete CRDs
    log_info "Deleting MetalLB CRDs..."
    kubectl get crd -o name 2>/dev/null | grep metallb | xargs kubectl delete 2>/dev/null || true

    # Delete namespace
    if kubectl get namespace metallb-system &> /dev/null; then
        kubectl delete namespace metallb-system --wait=true --timeout=60s 2>/dev/null || true
    fi

    log_success "MetalLB uninstalled"
}

#######################################
# Print summary
#######################################
print_summary() {
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}    Uninstall Complete!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""

    echo -e "${BLUE}Removed Components:${NC}"
    [[ "$UNINSTALL_MONITORING" == "true" ]] && echo "  - Monitoring stack"
    [[ "$UNINSTALL_METALLB" == "true" ]] && echo "  - MetalLB"
    [[ "$UNINSTALL_CLOUDFLARE" == "true" ]] && echo "  - Cloudflare Tunnel"
    echo ""

    echo -e "${BLUE}Verify Removal:${NC}"
    echo "  kubectl get namespaces"
    echo "  kubectl get pods -A"
    echo ""
}

#######################################
# Main
#######################################
main() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}  Observability Stack Uninstaller${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""

    parse_args "$@"
    confirm

    # Uninstall in reverse order of dependencies
    uninstall_cloudflare
    uninstall_monitoring
    uninstall_metallb

    print_summary
}

main "$@"
