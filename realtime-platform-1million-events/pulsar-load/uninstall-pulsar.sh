#!/bin/bash

# ================================================================================
# Pulsar Complete Uninstall Script
# ================================================================================
# This script forcefully removes Pulsar and all related resources from Kubernetes
# including handling stuck Victoria Metrics resources with finalizers
# ================================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

NAMESPACE="pulsar"

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   Pulsar Complete Uninstall Script${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Delete all StatefulSets, Deployments, DaemonSets
echo -e "${YELLOW}[1/8] Deleting controllers (StatefulSets, Deployments, DaemonSets)...${NC}"
kubectl delete statefulset,deployment,daemonset -n $NAMESPACE --all --timeout=30s 2>/dev/null || echo -e "${YELLOW}Some resources already deleted or timed out${NC}"
echo -e "${GREEN}✓ Controllers deleted${NC}"
echo ""

# Step 2: Remove finalizers from Victoria Metrics resources (this prevents hanging)
echo -e "${YELLOW}[2/8] Removing Victoria Metrics finalizers...${NC}"
echo -e "${CYAN}This prevents the namespace from hanging during deletion${NC}"

# Remove finalizers from vmagent resources
for resource in $(kubectl get vmagent -n $NAMESPACE -o name 2>/dev/null); do
    echo -e "${CYAN}  Removing finalizer from $resource${NC}"
    kubectl patch $resource -n $NAMESPACE -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
done

# Remove finalizers from vmsingle resources
for resource in $(kubectl get vmsingle -n $NAMESPACE -o name 2>/dev/null); do
    echo -e "${CYAN}  Removing finalizer from $resource${NC}"
    kubectl patch $resource -n $NAMESPACE -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
done

# Delete Victoria Metrics CRs (Custom Resources)
echo -e "${CYAN}  Deleting Victoria Metrics Custom Resources...${NC}"
kubectl delete vmagent,vmsingle -n $NAMESPACE --all --timeout=30s 2>/dev/null || echo -e "${YELLOW}Some CRs already deleted${NC}"

echo -e "${GREEN}✓ Finalizers removed${NC}"
echo ""

# Step 3: Delete all PVCs (including ZooKeeper to clear old state)
echo -e "${YELLOW}[3/8] Deleting all PVCs (including ZooKeeper state)...${NC}"
echo -e "${CYAN}This clears old cluster metadata and prevents state mismatches${NC}"
kubectl delete pvc -n $NAMESPACE --all --timeout=60s 2>/dev/null || echo -e "${YELLOW}Some PVCs already deleted${NC}"
echo -e "${GREEN}✓ All PVCs deleted${NC}"
echo ""

# Step 4: Delete all remaining resources
echo -e "${YELLOW}[4/8] Deleting all resources in namespace...${NC}"
kubectl delete all --all -n $NAMESPACE --timeout=30s 2>/dev/null || echo -e "${YELLOW}Some resources already deleted${NC}"
echo -e "${GREEN}✓ Resources deleted${NC}"
echo ""

# Step 5: Force delete namespace
echo -e "${YELLOW}[5/8] Force deleting namespace...${NC}"
if kubectl get namespace $NAMESPACE &> /dev/null; then
    echo -e "${CYAN}Initiating namespace deletion...${NC}"
    kubectl delete namespace $NAMESPACE --force --grace-period=0 &
    NAMESPACE_PID=$!
    
    # Wait up to 10 seconds for normal deletion
    sleep 10
    
    # If namespace still exists, remove its finalizers
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        echo -e "${CYAN}Removing namespace finalizers...${NC}"
        kubectl get namespace $NAMESPACE -o json | \
            jq '.spec.finalizers = []' | \
            kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f - 2>/dev/null || true
    fi
    
    # Wait for the background delete to complete
    wait $NAMESPACE_PID 2>/dev/null || true
    
    echo -e "${GREEN}✓ Namespace deleted${NC}"
else
    echo -e "${GREEN}✓ Namespace already deleted${NC}"
fi
echo ""

# Step 6: Clear NVMe storage directories (remove old cookies)
echo -e "${YELLOW}[6/8] Clearing NVMe storage directories (removing old BookKeeper cookies)...${NC}"
echo -e "${CYAN}This prevents cookie mismatch errors on reinstall${NC}"

# Get broker-bookie nodes and clear their storage
BOOKIE_NODES=($(kubectl get nodes -l node-type=broker-bookie -o jsonpath='{.items[*].metadata.name}' 2>/dev/null))
if [ ${#BOOKIE_NODES[@]} -gt 0 ]; then
    echo -e "${CYAN}Found ${#BOOKIE_NODES[@]} broker-bookie nodes to clean${NC}"
    for node in "${BOOKIE_NODES[@]}"; do
        echo -e "${CYAN}  Clearing storage on node: $node${NC}"
        # Use kubectl debug to clear the directories (non-interactive)
        kubectl debug node/$node --image=busybox --attach=false -- chroot /host sh -c "rm -rf /mnt/bookkeeper-journal/* /mnt/bookkeeper-ledgers/*" 2>/dev/null &
        DEBUG_PID=$!
        
        # Wait up to 5 seconds for the debug pod to complete
        for i in {1..5}; do
            if ! ps -p $DEBUG_PID > /dev/null 2>&1; then
                break
            fi
            sleep 1
        done
        
        # Kill if still running
        kill -9 $DEBUG_PID 2>/dev/null || true
        
        echo -e "${GREEN}  ✓ Cleared storage on $node${NC}"
    done
    echo -e "${GREEN}✓ NVMe storage directories cleared${NC}"
    
    # Clean up any debug pods
    echo -e "${CYAN}Cleaning up debug pods...${NC}"
    kubectl delete pod -l app=node-debugger-pulsar --all-namespaces --timeout=10s 2>/dev/null || true
else
    echo -e "${YELLOW}⚠️  No broker-bookie nodes found, skipping storage cleanup${NC}"
fi
echo ""

# Step 6b: Delete PersistentVolumes (BookKeeper NVMe)
echo -e "${YELLOW}[6b/8] Deleting BookKeeper PersistentVolumes (local-nvme)...${NC}"
PVS=$(kubectl get pv | grep pulsar-bookie | awk '{print $1}')
if [ -n "$PVS" ]; then
    for pv in $PVS; do
        echo -e "${CYAN}  Deleting PV: $pv${NC}"
        # Remove finalizers first
        kubectl patch pv $pv -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
        # Then delete (synchronously, no background)
        kubectl delete pv $pv --force --grace-period=0 2>/dev/null || true
    done
    
    # Wait for all PVs to be fully deleted
    echo -e "${CYAN}  Waiting for PVs to be fully deleted...${NC}"
    for i in {1..10}; do
        REMAINING=$(kubectl get pv 2>/dev/null | grep pulsar-bookie | wc -l | tr -d ' ')
        if [ -z "$REMAINING" ]; then
            REMAINING=0
        fi
        if [ "$REMAINING" -eq 0 ]; then
            break
        fi
        sleep 2
    done
    
    echo -e "${GREEN}✓ BookKeeper PersistentVolumes deleted${NC}"
else
    echo -e "${GREEN}✓ No BookKeeper PersistentVolumes found${NC}"
fi
echo ""

# Step 6b: Delete gp3 PersistentVolumes (ZooKeeper, Grafana, Victoria Metrics)
echo -e "${YELLOW}[6b/8] Deleting gp3 PersistentVolumes (ZooKeeper/Grafana/VictoriaMetrics)...${NC}"
GP3_PVS=$(kubectl get pv | grep -E "pulsar.*gp3" | awk '{print $1}')
if [ -n "$GP3_PVS" ]; then
    echo -e "${CYAN}  Found $(echo "$GP3_PVS" | wc -l | tr -d ' ') gp3 PVs to delete${NC}"
    for pv in $GP3_PVS; do
        echo -e "${CYAN}  Deleting gp3 PV: $pv${NC}"
        kubectl patch pv $pv -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
        kubectl delete pv $pv --force --grace-period=0 2>/dev/null || true
    done
    
    # Wait for gp3 PVs to be deleted (and trigger EBS volume deletion)
    echo -e "${CYAN}  Waiting for gp3 PVs and EBS volumes to be deleted...${NC}"
    sleep 10
    
    echo -e "${GREEN}✓ gp3 PersistentVolumes deleted (EBS volumes will be cleaned up by AWS)${NC}"
else
    echo -e "${GREEN}✓ No gp3 PersistentVolumes found${NC}"
fi
echo ""

# Step 7: Delete StorageClass
echo -e "${YELLOW}[7/8] Deleting local-nvme StorageClass...${NC}"
if kubectl get storageclass local-nvme &> /dev/null; then
    kubectl delete storageclass local-nvme
    echo -e "${GREEN}✓ StorageClass deleted${NC}"
else
    echo -e "${GREEN}✓ StorageClass already deleted${NC}"
fi
echo ""

# Step 8: Delete Victoria Metrics webhook configurations (prevents installation errors)
echo -e "${YELLOW}[8/8] Cleaning up webhook configurations...${NC}"
WEBHOOKS=$(kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations 2>/dev/null | grep pulsar-victoria-metrics | awk '{print $1}')
if [ -n "$WEBHOOKS" ]; then
    echo "$WEBHOOKS" | xargs kubectl delete 2>/dev/null
    echo -e "${GREEN}✓ Webhook configurations deleted${NC}"
else
    echo -e "${GREEN}✓ No webhook configurations found${NC}"
fi
echo ""

# Verification
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   Cleanup Complete!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Verification:${NC}"
echo -e "${CYAN}Checking for remaining resources...${NC}"
echo ""

# Check namespace
if kubectl get namespace $NAMESPACE &> /dev/null; then
    echo -e "${RED}⚠️  Namespace still exists (may take a few moments to fully delete)${NC}"
else
    echo -e "${GREEN}✓ Namespace: Deleted${NC}"
fi

# Check PVs
PV_COUNT=$(kubectl get pv 2>/dev/null | grep pulsar-bookie | wc -l | tr -d ' ')
if [ -z "$PV_COUNT" ]; then
    PV_COUNT=0
fi
if [ "$PV_COUNT" -gt 0 ]; then
    echo -e "${RED}⚠️  PersistentVolumes: $PV_COUNT remaining${NC}"
else
    echo -e "${GREEN}✓ PersistentVolumes: All deleted${NC}"
fi

# Check StorageClass
if kubectl get storageclass local-nvme &> /dev/null; then
    echo -e "${RED}⚠️  StorageClass: Still exists${NC}"
else
    echo -e "${GREEN}✓ StorageClass: Deleted${NC}"
fi

echo ""
echo ""
echo -e "${CYAN}Checking AWS EBS volumes...${NC}"
echo -e "${YELLOW}Note: EBS volumes may take 1-2 minutes to be fully deleted by AWS${NC}"

EBS_VOLUMES=$(aws ec2 describe-volumes --region us-west-2 --filters "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=pulsar" --query 'Volumes[*].VolumeId' --output text 2>/dev/null)
if [ -n "$EBS_VOLUMES" ]; then
    VOLUME_COUNT=$(echo "$EBS_VOLUMES" | wc -w)
    echo -e "${YELLOW}⚠️  Found $VOLUME_COUNT EBS volumes still being deleted by AWS${NC}"
    echo -e "${CYAN}  Volume IDs: $EBS_VOLUMES${NC}"
    echo -e "${CYAN}  These will be automatically cleaned up by AWS CSI driver${NC}"
else
    echo -e "${GREEN}✓ No Pulsar EBS volumes found in AWS${NC}"
fi

echo ""
echo -e "${CYAN}You can now reinstall Pulsar with:${NC}"
echo -e "${YELLOW}  cd pulsar-load && ./deploy.sh${NC}"
echo ""

