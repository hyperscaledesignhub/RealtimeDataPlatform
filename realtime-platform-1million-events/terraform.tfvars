# ================================================================================
# ALL SERVICES DEPLOYMENT - SINGLE AZ OPTIMIZED
# ================================================================================
# This configuration deploys the complete benchmark stack:
#   - Flink (2 node groups): JobManager, TaskManager
#   - Pulsar (3 node groups): ZooKeeper, Broker-Bookie, Proxy
#   - ClickHouse (2 node groups): Database cluster, Query nodes
#   - Producer (1 node group): IoT data generators
#   - General (1 node group): Shared services
# Total: 9 node groups, all in single AZ (us-west-2a) for cost savings
# Estimated Cost: ~$500-600/month (on-demand), ~$250-300/month (spot)

# Enable all services
enable_flink = true
enable_pulsar = true
enable_clickhouse = true
enable_general_nodes = true

# Disable Flink operator in Terraform (will be installed via deploy.sh)
install_flink_operator = false

# Cost optimization
use_spot_instances = false

# Flink configuration
flink_taskmanager_desired_size = 6
flink_jobmanager_desired_size = 1

# Pulsar configuration
pulsar_zookeeper_desired_size = 3
pulsar_broker_desired_size = 4  # Combined broker-bookie
pulsar_proxy_desired_size = 3

# ClickHouse configuration
clickhouse_desired_size = 6
clickhouse_query_desired_size = 1

# Producer configuration
producer_desired_size = 4

# General nodes configuration
general_desired_size = 4

# Cluster configuration
cluster_name = "benchmark-high-infra"
aws_region = "us-west-2"
environment = "production"
