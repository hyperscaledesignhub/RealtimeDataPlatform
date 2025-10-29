#!/bin/bash

# Get all broker-bookie nodes
BOOKIE_NODES=($(kubectl get nodes -l node-type=broker-bookie -o jsonpath='{.items[*].metadata.name}'))

echo "Found ${#BOOKIE_NODES[@]} broker-bookie nodes"

# Create PVs for each node
for i in "${!BOOKIE_NODES[@]}"; do
  NODE_NAME="${BOOKIE_NODES[$i]}"
  echo "Creating PVs for node $i: $NODE_NAME"
  
  # Create Journal PV
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pulsar-bookie-journal-pulsar-bookie-${i}
spec:
  capacity:
    storage: 1700Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-nvme
  local:
    path: /mnt/bookkeeper-journal
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${NODE_NAME}
EOF

  # Create Ledgers PV
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pulsar-bookie-ledgers-pulsar-bookie-${i}
spec:
  capacity:
    storage: 1700Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-nvme
  local:
    path: /mnt/bookkeeper-ledgers
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${NODE_NAME}
EOF

  echo "✓ Created PVs for node $i"
done

echo "All PVs created!"

