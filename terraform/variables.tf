variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "route53_zone_name" {
  description = "Route53 hosted zone name, for example dametech.net"
  type        = string
  default     = "dametech.net"
}

variable "wildcard_domain_name" {
  description = "Wildcard DNS name to issue and publish, for example *.openclaw.dametech.net"
  type        = string
  default     = "*.openclaw.dametech.net"
}

variable "existing_alb_name" {
  description = "Name of the existing shared public ALB"
  type        = string
  default     = "openclaw-alb"
}

variable "existing_https_listener_port" {
  description = "HTTPS listener port on the existing ALB"
  type        = number
  default     = 443
}

variable "ingress_target_ips" {
  description = "Private IP addresses for the ingress-nginx endpoint that the ALB should forward to"
  type        = list(string)
  default     = ["10.42.32.210"]
}
