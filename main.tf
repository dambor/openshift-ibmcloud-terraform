# main.tf

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = "~> 1.60"
    }
  }
}

provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region
}

# Get resource group
data "ibm_resource_group" "resource_group" {
  name = var.resource_group_name
}

# Create VPC
resource "ibm_is_vpc" "vpc" {
  name           = var.vpc_name
  resource_group  = data.ibm_resource_group.resource_group.id
  tags           = var.tags
}

# Create address prefixes
resource "ibm_is_vpc_address_prefix" "prefix" {
  count = length(var.zones)
  name  = "${var.vpc_name}-prefix-${count.index + 1}"
  zone  = var.zones[count.index]
  vpc   = ibm_is_vpc.vpc.id
  cidr  = var.zone_cidrs[count.index]
}

# Create public gateways
resource "ibm_is_public_gateway" "gateway" {
  count          = length(var.zones)
  name           = "${var.vpc_name}-gateway-${count.index + 1}"
  vpc            = ibm_is_vpc.vpc.id
  zone           = var.zones[count.index]
  resource_group = data.ibm_resource_group.resource_group.id
  tags           = var.tags
}

# Create subnets with explicit public gateway attachment
resource "ibm_is_subnet" "subnet" {
  count           = length(var.zones)
  name            = "${var.vpc_name}-subnet-${count.index + 1}"
  vpc             = ibm_is_vpc.vpc.id
  zone            = var.zones[count.index]
  ipv4_cidr_block = cidrsubnet(var.zone_cidrs[count.index], 4, 0)
  public_gateway  = ibm_is_public_gateway.gateway[count.index].id
  resource_group  = data.ibm_resource_group.resource_group.id
  tags            = var.tags

  depends_on = [ibm_is_public_gateway.gateway]
}

# Format subnets for OpenShift module
locals {
  vpc_subnets = {
    "default" = [
      for i, zone in var.zones : {
        id         = ibm_is_subnet.subnet[i].id
        zone       = zone
        cidr_block = ibm_is_subnet.subnet[i].ipv4_cidr_block
      }
    ]
    "zone-1" = [
      {
        id         = ibm_is_subnet.subnet[0].id
        zone       = var.zones[0]
        cidr_block = ibm_is_subnet.subnet[0].ipv4_cidr_block
      }
    ]
    "zone-2" = [
      {
        id         = ibm_is_subnet.subnet[1].id
        zone       = var.zones[1]
        cidr_block = ibm_is_subnet.subnet[1].ipv4_cidr_block
      }
    ]
    "zone-3" = [
      {
        id         = ibm_is_subnet.subnet[2].id
        zone       = var.zones[2]
        cidr_block = ibm_is_subnet.subnet[2].ipv4_cidr_block
      }
    ]
  }
}

# OpenShift Cluster
module "openshift_cluster" {
  source  = "terraform-ibm-modules/base-ocp-vpc/ibm"
  version = "~> 3.30"

  cluster_name      = var.cluster_name
  resource_group_id = data.ibm_resource_group.resource_group.id
  region            = var.region
  vpc_id            = ibm_is_vpc.vpc.id
  vpc_subnets       = local.vpc_subnets

  # OpenShift configuration
  ocp_version             = var.ocp_version
  disable_public_endpoint = var.disable_public_endpoint
  cluster_ready_when      = "IngressReady"
  
  # Enable outbound traffic (important for image pulls)
  disable_outbound_traffic_protection = true

  # Worker pools
  worker_pools = [
    {
      subnet_prefix     = "default"
      pool_name        = "default"
      machine_type     = var.worker_machine_type
      workers_per_zone = var.workers_per_zone
      operating_system = "REDHAT_8_64"
      labels = {
        environment = var.environment
        cluster     = var.cluster_name
      }
    }
  ]

  # Storage
  force_delete_storage    = true
  enable_registry_storage = true
  use_existing_cos       = false

  # Security - allow LoadBalancer traffic
  attach_ibm_managed_security_group = true
  additional_lb_security_group_ids  = [ibm_is_security_group.loadbalancer_sg.id]

  # Tags
  tags = var.tags

  depends_on = [ibm_is_subnet.subnet]
}

# Security group for LoadBalancers
resource "ibm_is_security_group" "loadbalancer_sg" {
  name           = "${var.vpc_name}-loadbalancer-sg"
  vpc            = ibm_is_vpc.vpc.id
  resource_group = data.ibm_resource_group.resource_group.id
  tags           = var.tags
}

# Allow HTTP traffic to LoadBalancers
resource "ibm_is_security_group_rule" "loadbalancer_http" {
  group     = ibm_is_security_group.loadbalancer_sg.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  tcp {
    port_min = 80
    port_max = 80
  }
}

# Allow HTTPS traffic to LoadBalancers
resource "ibm_is_security_group_rule" "loadbalancer_https" {
  group     = ibm_is_security_group.loadbalancer_sg.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  tcp {
    port_min = 443
    port_max = 443
  }
}

# Allow custom port range for applications
resource "ibm_is_security_group_rule" "loadbalancer_apps" {
  group     = ibm_is_security_group.loadbalancer_sg.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  tcp {
    port_min = 8000
    port_max = 9000
  }
}