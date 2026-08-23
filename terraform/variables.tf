# ---- Authentication ----
variable "tenancy_ocid" {
  description = "OCID of the tenancy (also the root compartment)"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the user whose API key signs requests"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API signing key"
  type        = string
}

variable "private_key_path" {
  description = "Absolute path to the API signing private key"
  type        = string
}

variable "region" {
  description = "OCI home region — Always Free resources only exist here"
  type        = string
  default     = "eu-frankfurt-1"
}

# ---- Project ----
variable "project_name" {
  description = "Prefix applied to every resource name"
  type        = string
  default     = "soc-lab"
}

variable "ssh_public_key" {
  description = "Public key injected into all instances for the default user"
  type        = string
}

# ---- Capacity handling ----
variable "arm_availability_domain" {
  description = "AD for the ARM instance. Rotated by the retry loop when capacity is exhausted."
  type        = string
  default     = "uKkk:EU-FRANKFURT-1-AD-1"
}
