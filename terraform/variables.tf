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

# ---- Network ----
variable "vcn_cidr" {
  description = "Address space for the whole lab network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Bastion tier — the only subnet with internet-routable hosts"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "SIEM and victim tier — outbound only, no inbound from internet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form. The ONLY source allowed to SSH in."
  type        = string
}

# ---- Compute ----
variable "arm_ocpus" {
  description = "ARM cores. Always Free ceiling is 2 since June 2026."
  type        = number
  default     = 2
}

variable "arm_memory_gb" {
  description = "ARM memory. Always Free ceiling is 12 GB since June 2026."
  type        = number
  default     = 12
}

variable "boot_volume_gb" {
  description = "Per-instance boot volume. 3 x 50 = 150 GB of the 200 GB free allowance."
  type        = number
  default     = 50
}

variable "micro_availability_domain" {
  description = "AD for x86 micro instances. E2.1.Micro is only offered in one AD per tenancy."
  type        = string
  default     = "uKkk:EU-FRANKFURT-1-AD-1"
}

variable "create_arm_instance" {
  description = "Toggle for the ARM host so the x86 tier can be applied while ARM capacity is unavailable."
  type        = bool
  default     = true
}
