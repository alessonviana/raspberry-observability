#!/bin/bash
# Script to fix MetalLB namespace annotations

RELEASE_NAME=${1:-monitoring}
RELEASE_NAMESPACE=${2:-monitoring}

echo "Fixing MetalLB namespace annotations..."
echo "Release name: $RELEASE_NAME"
echo "Release namespace: $RELEASE_NAMESPACE"

# Check if namespace exists
if ! kubectl get namespace metallb &>/dev/null; then
    echo "Namespace 'metallb' does not exist. It will be created during installation."
    exit 0
fi

# Update namespace annotations to match new release name
echo "Updating annotations..."
kubectl annotate namespace metallb meta.helm.sh/release-name="$RELEASE_NAME" --overwrite
kubectl annotate namespace metallb meta.helm.sh/release-namespace="$RELEASE_NAMESPACE" --overwrite
kubectl label namespace metallb app.kubernetes.io/managed-by=Helm --overwrite

echo ""
echo "✓ MetalLB namespace annotations updated!"
echo ""
echo "You can now try installing again:"
echo "  helm install \"$RELEASE_NAME\" . --namespace \"$RELEASE_NAMESPACE\" --create-namespace --wait"

