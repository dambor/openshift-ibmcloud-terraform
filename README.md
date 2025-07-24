# OpenShift on IBM Cloud VPC

Simple Terraform configuration to deploy Red Hat OpenShift on IBM Cloud VPC.

## What gets created

- **VPC** with 3 availability zones and public gateways
- **Subnets** in each zone with internet connectivity
- **OpenShift cluster** with worker nodes (2 per zone by default)
- **Cloud Object Storage** for OpenShift internal registry
- **Security groups** and network ACLs optimized for OpenShift

## Prerequisites

1. **IBM Cloud CLI** installed and configured
2. **Terraform** >= 1.3.0
3. **IBM Cloud API key** with sufficient permissions
4. **jq** (for the hibernation script)

### Required IBM Cloud Permissions
- VPC Infrastructure Services: Administrator
- Kubernetes Service: Administrator  
- Cloud Object Storage: Editor
- Resource Groups: Viewer

## Quick Start

1. **Set your API key:**
   ```bash
   export IC_API_KEY="your-api-key"
   ```
   Or edit `terraform.tfvars` and set `ibmcloud_api_key`

2. **Initialize Terraform:**
   ```bash
   terraform init
   ```

3. **Plan the deployment:**
   ```bash
   terraform plan
   ```

4. **Deploy:**
   ```bash
   terraform apply
   ```

5. **Get cluster access:**
   ```bash
   ibmcloud oc cluster config --cluster $(terraform output -raw cluster_name)
   kubectl get nodes
   ```

## Configuration

Edit `terraform.tfvars` to customize:

- `cluster_name` - Name of your OpenShift cluster
- `worker_machine_type` - Size of worker nodes (bx2.4x16, bx2.8x32, etc.)
- `workers_per_zone` - Number of workers per zone (default: 2)
- `zones` - Which availability zones to use (default: 3 zones)
- `disable_public_endpoint` - Set to true for private-only cluster

### Example customizations:

```hcl
# High-performance setup
worker_machine_type = "bx2.16x64"
workers_per_zone   = 3

# Cost-optimized setup  
worker_machine_type = "bx2.2x8"
workers_per_zone   = 1
zones = ["us-south-1", "us-south-2"]  # Only 2 zones
```

## Accessing Your Cluster

### Web Console
```bash
# Get console URL
echo "https://console-openshift-console.$(terraform output -raw ingress_hostname)"

# Login with your IBM Cloud credentials or kubeadmin
```

### Command Line
```bash
# Configure kubectl/oc
ibmcloud oc cluster config --cluster $(terraform output -raw cluster_name)

# Verify access
kubectl get nodes
oc get co  # Check cluster operators
```

### Get Admin Credentials
```bash
# Get admin password (if needed)
ibmcloud oc cluster get --cluster $(terraform output -raw cluster_name) --show-resources
```

## Cost Management

### 💰 Hibernation (Recommended for Development)

Use the included hibernation script to save money when not using the cluster:

```bash
# Make script executable
chmod +x cluster-hibernate.sh

# Hibernate cluster (scales workers to 0)
./cluster-hibernate.sh hibernate

# Wake up cluster (restores original worker count)
./cluster-hibernate.sh wake

# Check hibernation status
./cluster-hibernate.sh status
```

**Hibernation savings:** ~$15-30/day (workers stop billing, master continues)

### 🔥 Complete Shutdown (Maximum Savings)

```bash
# Destroy everything (maximum cost savings)
terraform destroy

# Recreate when needed
terraform apply
```

## Troubleshooting

### Common Issues

1. **"Resource group not found"**
   ```bash
   # Check available resource groups (case-sensitive!)
   ibmcloud resource groups
   
   # Update terraform.tfvars with correct name
   resource_group_name = "Default"  # Note the capital D
   ```

2. **"Can't pull container images"**
   - This is fixed automatically with `disable_outbound_traffic_protection = true`
   - If still failing, check public gateways are attached:
   ```bash
   ibmcloud is subnets --vpc $(terraform output -raw vpc_id)
   ```

3. **"Insufficient zones blocks"**
   - Ensure your zones are valid for your region:
   ```bash
   ibmcloud is zones us-south
   ```

4. **Workers not ready**
   ```bash
   # Check worker status
   ibmcloud oc workers --cluster $(terraform output -raw cluster_name)
   
   # Check cluster events  
   kubectl get events --all-namespaces
   ```

### Debug Commands

```bash
# Check cluster status
ibmcloud oc cluster get --cluster $(terraform output -raw cluster_name)

# Test connectivity from inside cluster
kubectl run debug --image=busybox --rm -it --restart=Never -- /bin/sh

# Check VPC resources
ibmcloud is vpcs
ibmcloud is subnets --vpc $(terraform output -raw vpc_id)
ibmcloud is public-gateways
```

## Cleanup

# Destroy everything (maximum savings)
terraform destroy
```
