variable "region" {
  type        = string
  description = "Default project region."
  default     = "eu-central-1"
}

variable "environment" {
  type        = string
  description = "Deployment environment name."
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}

variable "project_name" {
  type        = string
  description = "Shared name for all resource associated with the Cloud resume project."
  default     = "cloud-resume"
}