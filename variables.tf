# variables.tf

variable "ibmcloud_api_key" {
  description = "IBM Cloud API key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "IBM Cloud region"
  type        = string
  default     = "us-south"
}

variable "resource_group_name" {
  description = "Name of the IBM Cloud resource group"
  type        = string
  default     = "default"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "openshift"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "openshift-vpc"
}

variable "cluster_name" {
  description = "Name of the OpenShift cluster"
  type        = string
  default     = "openshift-cluster"
}

variable "zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-south-1", "us-south-2", "us-south-3"]
}

variable "zone_cidrs" {
  description = "CIDR blocks for each zone"
  type        = list(string)
  default     = ["10.10.0.0/18", "10.10.64.0/18", "10.10.128.0/18"]
}

variable "ocp_version" {
  description = "OpenShift version (null for latest)"
  type        = string
  default     = null
}

variable "disable_public_endpoint" {
  description = "Disable public service endpoint"
  type        = bool
  default     = false
}

variable "worker_machine_type" {
  description = "Machine type for worker nodes"
  type        = string
  default     = "bx2.4x16"
}

variable "workers_per_zone" {
  description = "Number of worker nodes per zone"
  type        = number
  default     = 2
}

variable "tags" {
  description = "List of tags"
  type        = list(string)
  default     = ["terraform", "openshift"]
}