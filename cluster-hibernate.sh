#!/bin/bash

# cluster-hibernate.sh - Hibernate and wake up OpenShift cluster on IBM Cloud

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get cluster name from Terraform
get_cluster_name() {
    if [[ -f "terraform.tfstate" ]]; then
        CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null)
    fi
    
    if [[ -z "$CLUSTER_NAME" ]]; then
        print_error "Could not get cluster name from Terraform output"
        print_status "Available clusters:"
        ibmcloud oc clusters --output table
        echo
        read -p "Enter cluster name: " CLUSTER_NAME
    fi
    
    if [[ -z "$CLUSTER_NAME" ]]; then
        print_error "No cluster name provided"
        exit 1
    fi
}

# Function to check cluster status
check_cluster_status() {
    local cluster_name="$1"
    
    local status
    status=$(ibmcloud oc cluster get --cluster "$cluster_name" --output json 2>/dev/null | jq -r '.state // "unknown"' 2>/dev/null)
    
    echo "$status"
}

# Function to get worker pool names
get_worker_pools() {
    local cluster_name="$1"
    
    ibmcloud oc worker-pools --cluster "$cluster_name" --output json | jq -r '.[].poolName'
}

# Function to hibernate cluster
hibernate_cluster() {
    local cluster_name="$1"
    
    print_status "Starting hibernation process for cluster: $cluster_name"
    
    # Check current status
    print_status "Checking cluster status for: $cluster_name"
    local current_status
    current_status=$(check_cluster_status "$cluster_name")
    print_status "Current cluster state: $current_status"
    
    if [[ "$current_status" != "normal" ]]; then
        print_warning "Cluster is not in 'normal' state. Current state: $current_status"
        read -p "Do you want to continue? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            print_status "Hibernation cancelled"
            return 0
        fi
    fi
    
    # Get worker pools
    local worker_pools
    worker_pools=$(get_worker_pools "$cluster_name")
    
    if [[ -z "$worker_pools" ]]; then
        print_error "No worker pools found for cluster: $cluster_name"
        return 1
    fi
    
    print_status "Found worker pools: $(echo "$worker_pools" | tr '\n' ' ')"
    
    print_warning "Note: IBM Cloud OpenShift requires a minimum of 2 workers per cluster"
    print_status "Hibernation will scale down to minimum viable size (1 worker per zone)"
    
    # Resize each worker pool to minimum (1 worker per zone)
    while IFS= read -r pool_name; do
        if [[ -n "$pool_name" ]]; then
            print_status "Resizing worker pool '$pool_name' to 1 worker per zone..."
            
            # Get current worker count
            local current_count
            current_count=$(ibmcloud oc worker-pool get --cluster "$cluster_name" --worker-pool "$pool_name" --output json | jq -r '.size // .sizePerZone // 2')
            
            # Ensure we have a valid number
            if [[ ! "$current_count" =~ ^[0-9]+$ ]]; then
                print_warning "Could not determine current worker count for pool '$pool_name', using default: 2"
                current_count=2
            fi
            
            # Store original count in a file for later restoration
            echo "$pool_name:$current_count" >> "/tmp/${cluster_name}_original_counts.txt"
            
            # Resize to 1 worker per zone (minimum for OpenShift)
            if ! ibmcloud oc worker-pool resize --cluster "$cluster_name" --worker-pool "$pool_name" --size-per-zone 1; then
                print_error "Failed to resize worker pool: $pool_name"
                return 1
            fi
            
            print_success "Worker pool '$pool_name' resize initiated (was $current_count workers per zone)"
        fi
    done <<< "$worker_pools"
    
    print_success "Hibernation initiated for cluster: $cluster_name"
    print_status "All worker pools have been resized to minimum viable size (1 per zone)"
    print_status "Original worker counts saved to: /tmp/${cluster_name}_original_counts.txt"
    print_warning "Note: The cluster master and minimum workers will continue running"
    
    # Monitor the hibernation process
    print_status "Monitoring hibernation progress..."
    local max_wait=1800  # 30 minutes
    local wait_time=0
    
    # Get number of zones to calculate expected minimum workers
    local zone_count
    zone_count=$(echo "$worker_pools" | wc -l)
    local expected_workers=$zone_count  # 1 worker per zone
    
    while [[ $wait_time -lt $max_wait ]]; do
        local current_worker_count
        current_worker_count=$(ibmcloud oc workers --cluster "$cluster_name" --output json | jq '[.[] | select(.state == "normal")] | length')
        
        if [[ "$current_worker_count" -le "$expected_workers" ]]; then
            print_success "Cluster hibernation complete! Scaled down to minimum workers ($current_worker_count)."
            break
        fi
        
        print_status "Still scaling down workers... ($current_worker_count workers remaining)"
        sleep 60
        wait_time=$((wait_time + 60))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        print_warning "Hibernation is taking longer than expected. Check manually with:"
        echo "ibmcloud oc workers --cluster $cluster_name"
    fi
}

# Function to wake up cluster
wake_cluster() {
    local cluster_name="$1"
    
    print_status "Starting wake-up process for cluster: $cluster_name"
    
    # Check if original counts file exists
    local counts_file="/tmp/${cluster_name}_original_counts.txt"
    if [[ ! -f "$counts_file" ]]; then
        print_error "Original worker counts file not found: $counts_file"
        print_status "You'll need to manually specify worker pool sizes"
        
        # Get worker pools and ask for sizes
        local worker_pools
        worker_pools=$(get_worker_pools "$cluster_name")
        
        echo
        print_status "Available worker pools:"
        echo "$worker_pools"
        echo
        
        while IFS= read -r pool_name; do
            if [[ -n "$pool_name" ]]; then
                echo -n "Enter number of workers per zone for pool '$pool_name' (default: 2): "
                read worker_count
                worker_count=${worker_count:-2}
                
                # Validate input is a number
                if [[ ! "$worker_count" =~ ^[0-9]+$ ]]; then
                    print_warning "Invalid number '$worker_count', using default: 2"
                    worker_count=2
                fi
                
                echo "$pool_name:$worker_count" >> "$counts_file"
                print_status "Will restore pool '$pool_name' to $worker_count workers per zone"
            fi
        done <<< "$worker_pools"
    else
        # Check if the counts file has valid data
        if grep -q ":null" "$counts_file" || grep -q ":$" "$counts_file"; then
            print_warning "Original counts file contains invalid data, recreating..."
            rm "$counts_file"
            
            # Get worker pools and ask for sizes
            local worker_pools
            worker_pools=$(get_worker_pools "$cluster_name")
            
            while IFS= read -r pool_name; do
                if [[ -n "$pool_name" ]]; then
                    echo
                    read -p "Enter number of workers for pool '$pool_name' (default: 2): " worker_count
                    worker_count=${worker_count:-2}
                    
                    # Validate input is a number
                    if [[ ! "$worker_count" =~ ^[0-9]+$ ]]; then
                        print_warning "Invalid number '$worker_count', using default: 2"
                        worker_count=2
                    fi
                    
                    echo "$pool_name:$worker_count" >> "$counts_file"
                fi
            done <<< "$worker_pools"
        fi
    fi
    
    print_status "Restoring worker pools from: $counts_file"
    
    # Restore each worker pool
    while IFS=':' read -r pool_name original_count; do
        if [[ -n "$pool_name" && -n "$original_count" ]]; then
            # Validate the original count is a number
            if [[ ! "$original_count" =~ ^[0-9]+$ ]]; then
                print_warning "Invalid worker count '$original_count' for pool '$pool_name', using default: 2"
                original_count=2
            fi
            
            print_status "Restoring worker pool '$pool_name' to $original_count workers..."
            
            if ! ibmcloud oc worker-pool resize --cluster "$cluster_name" --worker-pool "$pool_name" --size-per-zone "$original_count"; then
                print_error "Failed to restore worker pool: $pool_name"
                continue
            fi
            
            print_success "Worker pool '$pool_name' restore initiated"
        fi
    done < "$counts_file"
    
    print_success "Wake-up initiated for cluster: $cluster_name"
    print_status "Worker pools are being restored to original sizes"
    
    # Monitor the wake-up process
    print_status "Monitoring wake-up progress..."
    local max_wait=2700  # 45 minutes
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local ready_workers
        local total_workers
        ready_workers=$(ibmcloud oc workers --cluster "$cluster_name" --output json | jq '[.[] | select(.state == "normal")] | length')
        total_workers=$(ibmcloud oc workers --cluster "$cluster_name" --output json | jq '. | length')
        
        if [[ "$ready_workers" -gt 0 ]] && [[ "$ready_workers" -eq "$total_workers" ]]; then
            print_success "Cluster wake-up complete! All workers are ready."
            break
        fi
        
        print_status "Workers status: $ready_workers/$total_workers ready"
        sleep 120  # Check every 2 minutes
        wait_time=$((wait_time + 120))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        print_warning "Wake-up is taking longer than expected. Check manually with:"
        echo "ibmcloud oc workers --cluster $cluster_name"
    fi
    
    # Clean up the counts file
    if [[ -f "$counts_file" ]]; then
        rm "$counts_file"
        print_status "Cleaned up temporary file: $counts_file"
    fi
}

# Function to show cluster cost estimation
show_cost_info() {
    local cluster_name="$1"
    
    print_status "Cost Information for cluster: $cluster_name"
    echo
    echo "💰 Hibernation Savings:"
    echo "  - Worker nodes: Reduced to minimum (1 per zone)"
    echo "  - Master nodes: ~\$0.27/hour (still running)"
    echo "  - Storage: ~\$0.10/hour (persistent volumes)"
    echo
    echo "💡 Typical savings: ~60-80% of worker costs"
    echo "   Example: 6 workers → 3 workers = ~\$240/month savings"
    echo
    echo "⚠️  Note: OpenShift requires minimum 2 total workers (1 per zone)"
    echo "   For maximum savings, consider 'terraform destroy' instead"
    echo
    echo "🚀 For even more savings:"
    echo "   - Use smaller worker node types (bx2.2x8 instead of bx2.4x16)"
    echo "   - Reduce to 2 zones instead of 3"
    echo "   - Use 'terraform destroy' for weekends/extended periods"
}

# Function to list hibernated clusters
list_hibernated() {
    print_status "Checking for hibernated clusters..."
    echo
    
    # Get all clusters
    local clusters
    clusters=$(ibmcloud oc clusters --output json | jq -r '.[].name')
    
    echo "Cluster Status:"
    echo "==============="
    
    while IFS= read -r cluster_name; do
        if [[ -n "$cluster_name" ]]; then
            local worker_count
            worker_count=$(ibmcloud oc workers --cluster "$cluster_name" --output json 2>/dev/null | jq '. | length' 2>/dev/null || echo "unknown")
            
            local status
            status=$(check_cluster_status "$cluster_name")
            
            if [[ "$worker_count" == "0" ]]; then
                echo -e "🌙 ${YELLOW}$cluster_name${NC} - HIBERNATED (status: $status)"
            elif [[ "$worker_count" == "unknown" ]]; then
                echo -e "❓ ${RED}$cluster_name${NC} - STATUS UNKNOWN"
            else
                echo -e "🟢 ${GREEN}$cluster_name${NC} - ACTIVE ($worker_count workers, status: $status)"
            fi
        fi
    done <<< "$clusters"
}

# Main function
main() {
    local action="$1"
    local cluster_name="$2"
    
    # Check if ibmcloud CLI is available and logged in
    if ! command -v ibmcloud &> /dev/null; then
        print_error "IBM Cloud CLI not found. Please install it first."
        exit 1
    fi
    
    if ! ibmcloud target &> /dev/null; then
        print_error "Not logged into IBM Cloud. Please run 'ibmcloud login' first."
        exit 1
    fi
    
    case "$action" in
        "hibernate"|"sleep")
            if [[ -z "$cluster_name" ]]; then
                get_cluster_name
            else
                CLUSTER_NAME="$cluster_name"
            fi
            hibernate_cluster "$CLUSTER_NAME"
            show_cost_info "$CLUSTER_NAME"
            ;;
        "wake"|"wakeup"|"resume")
            if [[ -z "$cluster_name" ]]; then
                get_cluster_name
            else
                CLUSTER_NAME="$cluster_name"
            fi
            wake_cluster "$CLUSTER_NAME"
            ;;
        "status"|"list")
            list_hibernated
            ;;
        "cost"|"costs")
            if [[ -z "$cluster_name" ]]; then
                get_cluster_name
            else
                CLUSTER_NAME="$cluster_name"
            fi
            show_cost_info "$CLUSTER_NAME"
            ;;
        *)
            echo "OpenShift Cluster Hibernation Tool"
            echo "================================="
            echo
            echo "Usage: $0 <action> [cluster-name]"
            echo
            echo "Actions:"
            echo "  hibernate, sleep    - Scale worker pools to 0 (hibernate cluster)"
            echo "  wake, wakeup, resume - Restore worker pools to original size"
            echo "  status, list        - Show hibernation status of all clusters"
            echo "  cost, costs         - Show cost information"
            echo
            echo "Examples:"
            echo "  $0 hibernate                    # Hibernate cluster from Terraform"
            echo "  $0 hibernate my-cluster         # Hibernate specific cluster"
            echo "  $0 wake                         # Wake cluster from Terraform"
            echo "  $0 status                       # Show all clusters status"
            echo
            echo "Notes:"
            echo "  - Master nodes continue running (and billing) during hibernation"
            echo "  - Worker pool sizes are automatically saved and restored"
            echo "  - Use 'terraform destroy' for complete cost savings"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"