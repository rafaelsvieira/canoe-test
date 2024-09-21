variable "vpc_name" {
  description = "(Optional) Specified the VPC name."
  type        = string
  default     = "my-vpc"
}

variable "vpc_cidr" {
  description = "(Optional) The IPv4 CIDR block for the VPC."
  type        = string
  default     = "10.0.1.0/24"
}

variable "region" {
  description = "(Optional) Specified the region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "(Optional) Specified deploy environment"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "(Optional) Specified the cluster name"
  type        = string
  default     = "canoe"
}

variable "acm_certificate_arn" {
  description = "Specified the ACM certificate ARN"
  type        = string
}

variable "ecr_name" {
  description = "(Optional) Specified the ECR name"
  type        = string
  default     = "canoe"
}

variable "image_uri" {
  description = "Specified the image URI"
  type        = string
}

variable "container_port" {
  description = "Specified the container port"
  type        = number
}
