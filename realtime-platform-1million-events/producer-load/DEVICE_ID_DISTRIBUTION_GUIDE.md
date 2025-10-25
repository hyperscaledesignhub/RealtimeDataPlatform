# Device ID Distribution in Kubernetes Deployment

## How Device ID Ranges are Assigned to Each Producer Instance

### Overview
When you deploy multiple replicas of the producer-perf application in Kubernetes, each pod automatically gets assigned a specific range of device IDs based on its instance number. This ensures no overlap and complete coverage of all 17,000 devices.

### Step-by-Step Process

#### 1. **Kubernetes Pod Naming Convention**
When you set `replicas: 2` in the deployment, Kubernetes creates pods with predictable names:
```
producer-perf-0    # Instance 0
producer-perf-1    # Instance 1
```

For `replicas: 3`:
```
producer-perf-0    # Instance 0
producer-perf-1    # Instance 1  
producer-perf-2    # Instance 2
```

#### 2. **Environment Variables in Pod**
Each pod gets these environment variables injected by Kubernetes:
```yaml
env:
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name  # This gives us "producer-perf-0", "producer-perf-1", etc.
- name: TOTAL_DEVICE_COUNT
  value: "17000"
- name: NUM_REPLICAS
  value: "2"  # Must match the replicas count in deployment
```

#### 3. **Entrypoint Script Logic**
The entrypoint script (`entrypoint.sh`) runs in each pod and:

1. **Extracts Instance Number**:
   ```bash
   # From POD_NAME="producer-perf-0" → INSTANCE_NUM=0
   # From POD_NAME="producer-perf-1" → INSTANCE_NUM=1
   INSTANCE_NUM=$(echo "${POD_NAME}" | grep -o '[0-9]*$')
   ```

2. **Calculates Device Range**:
   ```bash
   # For 17000 devices with 2 replicas:
   DEVICES_PER_INSTANCE=$((17000 / 2)) = 8500
   REMAINDER=$((17000 % 2)) = 0
   
   # Instance 0:
   DEVICE_ID_MIN=$((0 * 8500 + 1)) = 1
   DEVICE_ID_MAX=$((1 + 8500 - 1)) = 8500
   
   # Instance 1:
   DEVICE_ID_MIN=$((1 * 8500 + 1)) = 8501  
   DEVICE_ID_MAX=$((8501 + 8500 - 1)) = 17000
   ```

### Examples

#### Example 1: 2 Replicas (17000 devices)
```
Pod: producer-perf-0 (Instance 0)
├── Device IDs: 1 to 8500
├── Count: 8500 devices
└── Command: --device-id-min 1 --device-id-max 8500

Pod: producer-perf-1 (Instance 1)  
├── Device IDs: 8501 to 17000
├── Count: 8500 devices
└── Command: --device-id-min 8501 --device-id-max 17000
```

#### Example 2: 3 Replicas (17000 devices)
```
Pod: producer-perf-0 (Instance 0)
├── Device IDs: 1 to 5667
├── Count: 5667 devices
└── Command: --device-id-min 1 --device-id-max 5667

Pod: producer-perf-1 (Instance 1)
├── Device IDs: 5668 to 11333  
├── Count: 5666 devices
└── Command: --device-id-min 5668 --device-id-max 11333

Pod: producer-perf-2 (Instance 2)
├── Device IDs: 11334 to 17000
├── Count: 5667 devices  
└── Command: --device-id-min 11334 --device-id-max 17000
```

#### Example 3: 5 Replicas (17000 devices)
```
Pod: producer-perf-0 (Instance 0)
├── Device IDs: 1 to 3401
├── Count: 3401 devices

Pod: producer-perf-1 (Instance 1)
├── Device IDs: 3402 to 6801
├── Count: 3400 devices

Pod: producer-perf-2 (Instance 2)
├── Device IDs: 6802 to 10201
├── Count: 3400 devices

Pod: producer-perf-3 (Instance 3)
├── Device IDs: 10202 to 13601
├── Count: 3400 devices

Pod: producer-perf-4 (Instance 4)
├── Device IDs: 13602 to 17000
├── Count: 3399 devices
```

### Verification

#### Check Pod Logs
Each pod logs its configuration on startup:
```bash
kubectl logs producer-perf-0 -n pulsar
# Output:
# 🚀 IoT Performance Producer - Instance Configuration:
#    📊 Total Devices: 17000
#    🔢 Total Instances: 2
#    🏷️  Instance Number: 0
#    📱 Device ID Range: 1 to 8500 (8500 devices)

kubectl logs producer-perf-1 -n pulsar  
# Output:
# 🚀 IoT Performance Producer - Instance Configuration:
#    📊 Total Devices: 17000
#    🔢 Total Instances: 2
#    🏷️  Instance Number: 1
#    📱 Device ID Range: 8501 to 17000 (8500 devices)
```

#### Check Running Processes
```bash
kubectl exec producer-perf-0 -n pulsar -- ps aux
# Shows: IoTPerformanceProducer with --device-id-min 1 --device-id-max 8500

kubectl exec producer-perf-1 -n pulsar -- ps aux  
# Shows: IoTPerformanceProducer with --device-id-min 8501 --device-id-max 17000
```

### Key Points

1. **Automatic Distribution**: No manual configuration needed - each pod automatically calculates its range
2. **No Overlap**: Device IDs are distributed sequentially with no gaps or overlaps
3. **Equal Load**: Each instance handles approximately the same number of devices
4. **Scalable**: Just change `replicas` count in deployment to scale up/down
5. **Fault Tolerant**: If a pod restarts, it gets the same instance number and device range

### Deployment Commands

```bash
# Deploy with 2 replicas
kubectl apply -f producer-deployment-distributed.yaml

# Scale to 3 replicas
kubectl scale deployment producer-perf --replicas=3 -n pulsar

# Check pod status
kubectl get pods -n pulsar -l app=producer-perf

# View logs for specific instance
kubectl logs producer-perf-0 -n pulsar
```

This ensures that your 17,000 devices are perfectly distributed across all producer instances without any manual configuration!
