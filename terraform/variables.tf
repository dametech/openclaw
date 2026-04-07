variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-southeast-2"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "personal"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/au01-0.yaml"
}

variable "vpc_id" {
  description = "VPC ID for DAME-VPC"
  type        = string
  # Get with: aws ec2 describe-vpcs --filters "Name=tag:Name,Values=DAME-VPC" --query 'Vpcs[0].VpcId' --output text
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB (must be in at least 2 AZs)"
  type        = list(string)
  # Get with: aws ec2 describe-subnets --filters "Name=vpc-id,Values=VPC_ID" "Name=tag:Type,Values=public"
  default = []
}

variable "domain_name" {
  description = "Domain name for OpenClaw Teams webhook"
  type        = string
  default     = "openclaw.<your-domain>"
}

variable "route53_zone_name" {
  description = "Route53 hosted zone name (e.g., <your-domain>)"
  type        = string
  default     = "<your-domain>"
}

variable "k8s_worker_nodes" {
  description = "Internal IP addresses of Kubernetes worker nodes"
  type        = list(string)
  # Worker node IPs from: kubectl get nodes -o wide
  default = [
    "10.42.32.16",  # talos-cluster-one-worker-w01
    "10.42.32.17",  # talos-cluster-one-worker-w02
    "10.42.32.19",  # talos-cluster-one-worker-w04 (w03 disabled)
  ]
}

variable "k8s_nodeport" {
  description = "NodePort for OpenClaw Teams webhook service"
  type        = number
  default     = 30978
}

variable "health_check_path" {
  description = "Health check path for ALB target group"
  type        = string
  default     = "/"
}

variable "health_check_port" {
  description = "Port for health checks (OpenClaw gateway)"
  type        = number
  default     = 18789
}

variable "teams_webhook_path" {
  description = "Path for Teams webhook"
  type        = string
  default     = "/api/messages"
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on ALB"
  type        = bool
  default     = false  # Set to true for production
}

variable "domain_name" {
  description = "Domain name for OpenClaw (optional, for Route53)"
  type        = string
  default     = ""
  # Example: "openclaw.yourdomain.com"
}

variable "create_route53_record" {
  description = "Create Route53 A record for ALB"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID (required if create_route53_record = true)"
  type        = string
  default     = ""
}
