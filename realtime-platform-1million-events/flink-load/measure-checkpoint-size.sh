#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
S3_BUCKET="s3-platform-flink"
CHECKPOINT_PREFIX="flink-checkpoints/low-infra/"
SAVEPOINT_PREFIX="flink-savepoints/low-infra/"

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   Flink S3 Checkpoint Size Measurement Tool${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Install it with: brew install awscli (on macOS)"
    exit 1
fi

echo -e "${CYAN}S3 Bucket: ${NC}s3://${S3_BUCKET}"
echo ""

# Function to get size and count
get_s3_stats() {
    local prefix=$1
    local name=$2
    
    echo -e "${YELLOW}Analyzing ${name}...${NC}"
    
    # Get list of objects
    result=$(aws s3 ls "s3://${S3_BUCKET}/${prefix}" --recursive --summarize 2>&1)
    
    if echo "$result" | grep -q "NoSuchBucket\|NoSuchKey\|AccessDenied"; then
        echo -e "${RED}  ✗ No data found or access denied${NC}"
        echo ""
        return
    fi
    
    # Extract total size and count
    total_size=$(echo "$result" | grep "Total Size:" | awk '{print $3}')
    total_objects=$(echo "$result" | grep "Total Objects:" | awk '{print $3}')
    
    if [ -z "$total_size" ] || [ "$total_size" = "0" ]; then
        echo -e "${YELLOW}  ⚠ No checkpoints/savepoints found${NC}"
        echo ""
        return
    fi
    
    # Convert bytes to human-readable format
    if [ "$total_size" -lt 1024 ]; then
        size_hr="${total_size} B"
    elif [ "$total_size" -lt 1048576 ]; then
        size_hr=$(echo "scale=2; $total_size / 1024" | bc)" KB"
    elif [ "$total_size" -lt 1073741824 ]; then
        size_hr=$(echo "scale=2; $total_size / 1048576" | bc)" MB"
    else
        size_hr=$(echo "scale=2; $total_size / 1073741824" | bc)" GB"
    fi
    
    echo -e "${GREEN}  ✓ Total Size: ${size_hr}${NC}"
    echo -e "${GREEN}  ✓ Total Files: ${total_objects}${NC}"
    
    # Show latest checkpoints
    echo -e "${CYAN}  Latest items:${NC}"
    echo "$result" | grep -v "Total" | tail -5 | while read -r line; do
        echo "    $line"
    done
    echo ""
}

# Measure checkpoints
echo -e "${BLUE}──────────────────────────────────────────────────────────${NC}"
echo -e "${CYAN}1. CHECKPOINTS${NC}"
echo -e "${BLUE}──────────────────────────────────────────────────────────${NC}"
get_s3_stats "$CHECKPOINT_PREFIX" "Checkpoints"

# Measure savepoints
echo -e "${BLUE}──────────────────────────────────────────────────────────${NC}"
echo -e "${CYAN}2. SAVEPOINTS${NC}"
echo -e "${BLUE}──────────────────────────────────────────────────────────${NC}"
get_s3_stats "$SAVEPOINT_PREFIX" "Savepoints"

# Get detailed breakdown by job
echo -e "${BLUE}──────────────────────────────────────────────────────────${NC}"
echo -e "${CYAN}3. DETAILED BREAKDOWN BY JOB${NC}"
echo -e "${BLUE}──────────────────────────────────────────────────────────${NC}"

jobs=$(aws s3 ls "s3://${S3_BUCKET}/${CHECKPOINT_PREFIX}" 2>/dev/null | grep "PRE" | awk '{print $2}' | sed 's/\///')

if [ -z "$jobs" ]; then
    echo -e "${YELLOW}No job directories found${NC}"
else
    for job in $jobs; do
        echo -e "${YELLOW}Job: ${job}${NC}"
        
        # Get checkpoints for this job
        chk_result=$(aws s3 ls "s3://${S3_BUCKET}/${CHECKPOINT_PREFIX}${job}/" --recursive --summarize 2>&1)
        chk_size=$(echo "$chk_result" | grep "Total Size:" | awk '{print $3}')
        chk_count=$(echo "$chk_result" | grep "Total Objects:" | awk '{print $3}')
        
        if [ -n "$chk_size" ] && [ "$chk_size" != "0" ]; then
            # Convert to human readable
            if [ "$chk_size" -lt 1048576 ]; then
                chk_hr=$(echo "scale=2; $chk_size / 1024" | bc)" KB"
            elif [ "$chk_size" -lt 1073741824 ]; then
                chk_hr=$(echo "scale=2; $chk_size / 1048576" | bc)" MB"
            else
                chk_hr=$(echo "scale=2; $chk_size / 1073741824" | bc)" GB"
            fi
            
            echo -e "  Size: ${GREEN}${chk_hr}${NC}"
            echo -e "  Files: ${GREEN}${chk_count}${NC}"
            
            # List individual checkpoints
            echo -e "  ${CYAN}Checkpoints:${NC}"
            aws s3 ls "s3://${S3_BUCKET}/${CHECKPOINT_PREFIX}${job}/" 2>/dev/null | grep "PRE" | awk '{print $2}' | sed 's/\///' | while read -r chkpt; do
                chkpt_size=$(aws s3 ls "s3://${S3_BUCKET}/${CHECKPOINT_PREFIX}${job}/${chkpt}/" --recursive --summarize 2>/dev/null | grep "Total Size:" | awk '{print $3}')
                if [ -n "$chkpt_size" ]; then
                    if [ "$chkpt_size" -lt 1048576 ]; then
                        chkpt_hr=$(echo "scale=2; $chkpt_size / 1024" | bc)" KB"
                    else
                        chkpt_hr=$(echo "scale=2; $chkpt_size / 1048576" | bc)" MB"
                    fi
                    echo -e "    - chkpt-${chkpt}: ${chkpt_hr}"
                fi
            done
        else
            echo -e "  ${YELLOW}No checkpoints found${NC}"
        fi
        echo ""
    done
fi

# Summary
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   SUMMARY${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

total_result=$(aws s3 ls "s3://${S3_BUCKET}/flink-checkpoints/low-infra/" --recursive --summarize 2>&1)
total_size=$(echo "$total_result" | grep "Total Size:" | awk '{print $3}')

if [ -n "$total_size" ] && [ "$total_size" != "0" ]; then
    if [ "$total_size" -lt 1048576 ]; then
        total_hr=$(echo "scale=2; $total_size / 1024" | bc)" KB"
    elif [ "$total_size" -lt 1073741824 ]; then
        total_hr=$(echo "scale=2; $total_size / 1048576" | bc)" MB"
    else
        total_hr=$(echo "scale=2; $total_size / 1073741824" | bc)" GB"
    fi
    
    echo -e "${GREEN}Total Checkpoint Storage: ${total_hr}${NC}"
    
    # Calculate cost (S3 Standard pricing: $0.023 per GB/month)
    if [ "$total_size" -gt 0 ]; then
        size_gb=$(echo "scale=4; $total_size / 1073741824" | bc)
        cost=$(echo "scale=2; $size_gb * 0.023" | bc)
        echo -e "${CYAN}Estimated Monthly S3 Cost: \$${cost}${NC}"
    fi
else
    echo -e "${YELLOW}No checkpoint data found${NC}"
fi

echo ""
echo -e "${CYAN}Notes:${NC}"
echo "  - Incremental checkpoints only store deltas (efficient!)"
echo "  - Retention policy keeps last 3 checkpoints"
echo "  - Old checkpoints are automatically cleaned up"
echo ""

