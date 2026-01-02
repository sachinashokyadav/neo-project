variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_id" {
  description = "Existing VPC id"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (2 subnets)"
  type        = list(string)
  default     = [] # replace with ["subnet-aaa", "subnet-bbb"]
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs (2 subnets) for worker nodes"
  type        = list(string)
  default     = [] # replace with ["subnet-ccc", "subnet-ddd"]
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "eks"
}

variable "node_ami_type" {
  description = "Node AMI type"
  type        = string
  default     = "AL2023_x86_64_STANDARD" # change to AL2_x86_64/AL2_x86_64_GPU/AL2_ARM_64 if needed
}

variable "frontend_node_count" {
  type    = number
  default = 1
}

variable "backend_node_count" {
  type    = number
  default = 1
}

variable "database_node_count" {
  type    = number
  default = 1
}


variable "key_name" {
  description = "EC2 Key pair name for SSH access"
  type        = string
}
