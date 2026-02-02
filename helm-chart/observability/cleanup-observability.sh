#!/bin/bash
# Script to completely clean up observability installation

set -e

echo "========================================="
echo "Cleaning up observability installation..."
echo "========================================="

# 1. Remove Helm release
echo "Step 1: Removing Helm release..."
helm uninstall observability --namespace observability 2>/dev/null || echo "  No Helm release found"

# 2. Check for namespace and force delete if stuck
echo "Step 2: Checking namespace status..."
if kubectl get namespace observability &>/dev/null; then
    echo "  Namespace exists, checking if it's stuck..."
    STATUS=$(kubectl get namespace observability -o jsonpath='{.status.phase}')
    if [ "$STATUS" = "Terminating" ]; then
        echo "  Namespace is stuck in Terminating state, forcing cleanup..."
        kubectl get namespace observability -o json > /tmp/ns.json
        sed -i 's/"kubernetes"//' /tmp/ns.json
        kubectl replace --raw "/api/v1/namespaces/observability/finalize" -f /tmp/ns.json
        rm /tmp/ns.json
    fi
    echo "  Deleting namespace..."
    kubectl delete namespace observability --wait=true --timeout=120s 2>/dev/null || true
fi

# 3. Wait a bit for namespace to be fully deleted
echo "Step 3: Waiting for namespace deletion..."
sleep 5

# 4. Remove all resources in namespace (if namespace still exists)
echo "Step 4: Removing all resources in namespace..."
kubectl delete all --all -n observability 2>/dev/null || true
kubectl delete secrets --all -n observability 2>/dev/null || true
kubectl delete configmaps --all -n observability 2>/dev/null || true
kubectl delete serviceaccounts --all -n observability 2>/dev/null || true
kubectl delete roles --all -n observability 2>/dev/null || true
kubectl delete rolebindings --all -n observability 2>/dev/null || true
kubectl delete pvc --all -n observability 2>/dev/null || true

# 5. Remove cluster-scoped resources
echo "Step 5: Removing cluster-scoped resources..."
kubectl get clusterrole -o name | grep observability | xargs kubectl delete 2>/dev/null || true
kubectl get clusterrolebinding -o name | grep observability | xargs kubectl delete 2>/dev/null || true

# 6. Force delete namespace one more time
echo "Step 6: Force deleting namespace if still exists..."
kubectl delete namespace observability --grace-period=0 --force 2>/dev/null || true

# 7. Wait and verify
echo "Step 7: Verifying cleanup..."
sleep 3

if kubectl get namespace observability &>/dev/null; then
    echo "  WARNING: Namespace still exists!"
    echo "  You may need to manually edit the namespace to remove finalizers"
else
    echo "  ✓ Namespace deleted successfully"
fi

# 8. Check for remaining resources
echo "Step 8: Checking for remaining resources..."
REMAINING=$(kubectl get clusterrole,clusterrolebinding -o name 2>/dev/null | grep observability | wc -l)
if [ "$REMAINING" -gt 0 ]; then
    echo "  WARNING: Found $REMAINING remaining cluster-scoped resources"
    kubectl get clusterrole,clusterrolebinding -o name | grep observability
else
    echo "  ✓ No remaining cluster-scoped resources"
fi

echo ""
echo "========================================="
echo "Cleanup completed!"
echo "========================================="
echo ""
echo "You can now try installing again with:"
echo "  helm install observability . --namespace observability --create-namespace --wait"


