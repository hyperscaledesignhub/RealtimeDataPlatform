#!/bin/bash

# ================================================================================
# Setup S3 Checkpoints for Flink
# ================================================================================
# This script configures IAM permissions and updates Flink to use S3 for checkpoints
#
# USAGE:
#   ./setup-s3-checkpoints.sh                    # Use defaults (most common)
#   ./setup-s3-checkpoints.sh <bucket> <cluster> # Override defaults
#
# DEFAULTS (hardcoded):
#   S3 Bucket:   s3-platform-flink
#   EKS Cluster: benchmark-high-infra
#   Region:      us-west-2
#   Namespace:   flink-benchmark
#
# ================================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}      Flink S3 Checkpoints Setup${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Configuration - HARDCODED for convenience
NAMESPACE="flink-benchmark"
SERVICE_ACCOUNT="flink"

# Hardcoded defaults (can override with arguments)
DEFAULT_S3_BUCKET="s3-platform-flink"
DEFAULT_CLUSTER_NAME="benchmark-high-infra"

# Use arguments if provided, otherwise use defaults
S3_BUCKET="${1:-$DEFAULT_S3_BUCKET}"
CLUSTER_NAME="${2:-$DEFAULT_CLUSTER_NAME}"

REGION=$(aws configure get region || echo "us-west-2")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

# Function to list EKS clusters from ALL regions
list_eks_clusters() {
    echo -e "${BLUE}Scanning for EKS Clusters in all AWS regions...${NC}"
    echo ""
    
    # Get all AWS regions
    ALL_REGIONS=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null)
    
    if [ -z "$ALL_REGIONS" ]; then
        echo -e "${RED}Failed to get AWS regions${NC}"
        return
    fi
    
    FOUND_CLUSTERS=0
    
    for region in $ALL_REGIONS; do
        CLUSTERS=$(aws eks list-clusters --region "$region" --query 'clusters[]' --output text 2>/dev/null)
        
        if [ -n "$CLUSTERS" ]; then
            echo -e "${CYAN}Region: $region${NC}"
            for cluster in $CLUSTERS; do
                echo -e "  ${GREEN}✓${NC} $cluster"
                FOUND_CLUSTERS=$((FOUND_CLUSTERS + 1))
            done
            echo ""
        fi
    done
    
    if [ $FOUND_CLUSTERS -eq 0 ]; then
        echo -e "${YELLOW}No EKS clusters found in any region${NC}"
        echo ""
    else
        echo -e "${GREEN}Found $FOUND_CLUSTERS cluster(s) total${NC}"
        echo ""
    fi
}

# Validate inputs
if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}ERROR: AWS credentials not configured${NC}"
    echo ""
    echo "Configure AWS CLI first:"
    echo "  aws configure"
    exit 1
fi

# S3_BUCKET and CLUSTER_NAME now have defaults, so no validation needed
# Just show what values are being used
echo -e "${GREEN}Using Configuration:${NC}"
echo "  S3 Bucket: $S3_BUCKET"
echo "  EKS Cluster: $CLUSTER_NAME"
echo ""
echo -e "${YELLOW}Note: Override with: $0 <custom-bucket> <custom-cluster>${NC}"
echo ""

# Verify cluster exists and find its region
echo -e "${YELLOW}Verifying EKS cluster...${NC}"

CLUSTER_REGION=""
ALL_REGIONS=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null)

for region in $ALL_REGIONS; do
    if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$region" &>/dev/null; then
        CLUSTER_REGION="$region"
        break
    fi
done

if [ -z "$CLUSTER_REGION" ]; then
    echo -e "${RED}ERROR: Cluster '$CLUSTER_NAME' not found in any region${NC}"
    echo ""
    list_eks_clusters
    exit 1
fi

# Update REGION to the cluster's region
REGION="$CLUSTER_REGION"
echo -e "${GREEN}✓ Cluster found: $CLUSTER_NAME (region: $REGION)${NC}"
echo ""

echo -e "${CYAN}Configuration:${NC}"
echo "  AWS Region: $REGION"
echo "  AWS Account: $ACCOUNT_ID"
echo "  S3 Bucket: $S3_BUCKET"
echo "  EKS Cluster: $CLUSTER_NAME"
echo "  Namespace: $NAMESPACE"
echo "  Service Account: $SERVICE_ACCOUNT"
echo ""

# Step 1: Create S3 bucket if it doesn't exist
echo -e "${YELLOW}[1/6] Checking S3 bucket...${NC}"
if aws s3 ls "s3://$S3_BUCKET" 2>/dev/null; then
    echo -e "${GREEN}✓ Bucket exists: $S3_BUCKET${NC}"
else
    echo "Creating S3 bucket: $S3_BUCKET"
    aws s3 mb "s3://$S3_BUCKET" --region "$REGION"
    
    # Enable versioning for checkpoint recovery
    aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Set lifecycle policy to clean up old checkpoints
    cat > /tmp/s3-lifecycle.json <<EOF
{
  "Rules": [
    {
      "ID": "DeleteOldCheckpoints",
      "Status": "Enabled",
      "Prefix": "flink-checkpoints/high-infra/",
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 7
      },
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 1
      }
    }
  ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$S3_BUCKET" \
        --lifecycle-configuration file:///tmp/s3-lifecycle.json
    
    rm /tmp/s3-lifecycle.json
    
    echo -e "${GREEN}✓ Bucket created and configured${NC}"
fi
echo ""

# Step 2: Create IAM policy
echo -e "${YELLOW}[2/6] Creating IAM policy...${NC}"
POLICY_NAME="FlinkCheckpointsS3Policy-${CLUSTER_NAME}"

cat > /tmp/flink-s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET}",
        "arn:aws:s3:::${S3_BUCKET}/*"
      ]
    }
  ]
}
EOF

POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
    echo -e "${YELLOW}⚠ Policy already exists, updating...${NC}"
    aws iam create-policy-version \
        --policy-arn "$POLICY_ARN" \
        --policy-document file:///tmp/flink-s3-policy.json \
        --set-as-default
else
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///tmp/flink-s3-policy.json \
        --description "S3 permissions for Flink checkpoints"
    echo -e "${GREEN}✓ Policy created${NC}"
fi

rm /tmp/flink-s3-policy.json
echo ""

# Step 3: Get OIDC provider
echo -e "${YELLOW}[3/6] Getting EKS OIDC provider...${NC}"
OIDC_PROVIDER=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

if [ -z "$OIDC_PROVIDER" ]; then
    echo -e "${RED}✗ Failed to get OIDC provider${NC}"
    echo "Make sure OIDC provider is enabled for your EKS cluster"
    exit 1
fi

echo -e "${GREEN}✓ OIDC Provider: $OIDC_PROVIDER${NC}"
echo ""

# Step 4: Create IAM role for service account
echo -e "${YELLOW}[4/6] Creating IAM role for IRSA...${NC}"
ROLE_NAME="FlinkCheckpointsRole-${CLUSTER_NAME}"

cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo -e "${YELLOW}⚠ Role already exists, checking trust policy...${NC}"
    
    # Get current trust policy and check if OIDC provider matches
    CURRENT_OIDC=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Federated' --output text 2>/dev/null || echo "")
    EXPECTED_OIDC="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
    
    if [[ "$CURRENT_OIDC" != "$EXPECTED_OIDC" ]]; then
        echo -e "${YELLOW}⚠ OIDC provider mismatch detected!${NC}"
        echo "  Current:  $CURRENT_OIDC"
        echo "  Expected: $EXPECTED_OIDC"
        echo -e "${YELLOW}  Updating trust policy...${NC}"
        
        aws iam update-assume-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-document file:///tmp/trust-policy.json
        
        echo -e "${GREEN}✓ Trust policy updated with correct OIDC provider${NC}"
    else
        echo -e "${GREEN}✓ Trust policy is correct${NC}"
    fi
else
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --description "IAM role for Flink checkpoints to S3"
    echo -e "${GREEN}✓ Role created${NC}"
fi

rm /tmp/trust-policy.json

# Attach policy to role
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN"

echo -e "${GREEN}✓ Policy attached to role${NC}"
echo ""

# Step 5: Annotate service account
echo -e "${YELLOW}[5/6] Annotating service account...${NC}"

kubectl annotate serviceaccount "$SERVICE_ACCOUNT" \
    -n "$NAMESPACE" \
    eks.amazonaws.com/role-arn="$ROLE_ARN" \
    --overwrite

echo -e "${GREEN}✓ Service account annotated${NC}"
echo ""

# Step 6: Update FlinkDeployment
echo -e "${YELLOW}[6/6] Updating FlinkDeployment configuration...${NC}"

cat <<EOF

To enable S3 checkpoints, update your flink-job-deployment.yaml:

1. Update checkpoint directories in flinkConfiguration:
   
   state.checkpoints.dir: s3://${S3_BUCKET}/flink-checkpoints/high-infra/
   state.savepoints.dir: s3://${S3_BUCKET}/flink-savepoints/high-infra/

2. Add S3 credential provider (REQUIRED for IRSA):
   
   fs.s3a.aws.credentials.provider: com.amazonaws.auth.WebIdentityTokenCredentialsProvider
   s3.path.style.access: "false"

3. Ensure S3 plugin is in Dockerfile:
   
   RUN mkdir -p /opt/flink/plugins/s3-fs-hadoop && \\
       cp /opt/flink/opt/flink-s3-fs-hadoop-1.18.0.jar /opt/flink/plugins/s3-fs-hadoop/

4. Rebuild Docker image with S3 plugin:
   
   ./build-and-push.sh

5. Apply the updated deployment:
   
   kubectl apply -f flink-job-deployment.yaml

6. Restart Flink to pick up new S3 configuration:
   
   kubectl delete flinkdeployment iot-flink-job -n ${NAMESPACE}
   kubectl apply -f flink-job-deployment.yaml

EOF

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ S3 Checkpoints Setup Complete!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Summary:${NC}"
echo "  S3 Bucket: s3://${S3_BUCKET}"
echo "  IAM Policy: ${POLICY_ARN}"
echo "  IAM Role: ${ROLE_ARN}"
echo "  Service Account: ${NAMESPACE}/${SERVICE_ACCOUNT}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Verify S3 paths in flink-job-deployment.yaml match (already configured)"
echo "  2. Apply: kubectl apply -f flink-job-deployment.yaml"
echo "  3. Restart Flink pods"
echo ""
echo -e "${CYAN}Verify checkpoints:${NC}"
echo "  aws s3 ls s3://${S3_BUCKET}/flink-checkpoints/high-infra/"
echo ""
echo -e "${GREEN}💡 TIP: Next time just run: ./setup-s3-checkpoints.sh${NC}"
echo -e "${GREEN}   (No arguments needed - using defaults!)${NC}"

