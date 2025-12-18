#!/bin/bash
# Script to configure MetalLB IPAddressPool and L2Advertisement
# Run this after installing the Helm chart if the automatic configuration fails

NAMESPACE=${1:-metallb}
IP_START=${2:-192.168.2.100}
IP_END=${3:-192.168.2.250}

echo "Configuring MetalLB in namespace: $NAMESPACE"
echo "IP Range: $IP_START - $IP_END"

# Create IPAddressPool
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: $NAMESPACE
spec:
  addresses:
  - $IP_START-$IP_END
EOF

# Create L2Advertisement
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2advertisement
  namespace: $NAMESPACE
spec:
  ipAddressPools:
  - default-pool
EOF

echo "MetalLB configuration completed!"
kubectl get ipaddresspool -n $NAMESPACE
kubectl get l2advertisement -n $NAMESPACE

