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
  default     = "vpc-DAME-VPC"  # Replace with actual VPC ID
}

variable "alb_arn" {
  description = "ARN of existing ALB for OpenClaw"
  type        = string
  default     = "arn:aws:elasticloadbalancing:ap-southeast-2:ACCOUNT:loadbalancer/app/openclaw-alb/56373705"  # Replace with actual ARN
}

variable "alb_listener_arn" {
  description = "ARN of HTTPS listener on ALB"
  type        = string
  # Replace with actual listener ARN
  # Format: arn:aws:elasticloadbalancing:REGION:ACCOUNT:listener/app/openclaw-alb/ID/LISTENER_ID
}

variable "k8s_worker_nodes" {
  description = "IP addresses of Kubernetes worker nodes"
  type        = list(string)
  default = [
    "10.42.XX.XX",  # Replace with actual node IPs from au01-0 cluster
    "10.42.XX.XX",
    "10.42.XX.XX",
    "10.42.XX.XX"
  ]
}

variable "k8s_nodeport" {
  description = "NodePort for OpenClaw Teams webhook service"
  type        = number
  default     = 30978  # NodePort for port 3978
}

variable "health_check_path" {
  description = "Health check path for ALB target group"
  type        = string
  default     = "/"  # OpenClaw gateway health endpoint
}

variable "teams_webhook_path" {
  description = "Path for Teams webhook"
  type        = string
  default     = "/api/messages"
}
