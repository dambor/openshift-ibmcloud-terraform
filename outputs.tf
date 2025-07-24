# outputs.tf

output "vpc_id" {
  description = "VPC ID"
  value       = ibm_is_vpc.vpc.id
}

output "vpc_crn" {
  description = "VPC CRN"
  value       = ibm_is_vpc.vpc.crn
}

output "subnet_ids" {
  description = "List of subnet IDs"
  value       = ibm_is_subnet.subnet[*].id
}

output "cluster_id" {
  description = "OpenShift cluster ID"
  value       = module.openshift_cluster.cluster_id
}

output "cluster_name" {
  description = "OpenShift cluster name"
  value       = module.openshift_cluster.cluster_name
}

output "cluster_crn" {
  description = "OpenShift cluster CRN"
  value       = module.openshift_cluster.cluster_crn
}

output "master_url" {
  description = "OpenShift master URL"
  value       = module.openshift_cluster.master_url
}

output "ingress_hostname" {
  description = "OpenShift ingress hostname"
  value       = module.openshift_cluster.ingress_hostname
}

output "console_url" {
  description = "OpenShift console URL"
  value       = "https://console-openshift-console.${module.openshift_cluster.ingress_hostname}"
}