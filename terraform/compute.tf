# ============================================================
# Images — resolved dynamically, never hardcoded
# ============================================================
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

data "oci_core_images" "ubuntu_x86" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ============================================================
# jumpbox — the only host reachable from the internet
# ============================================================
resource "oci_core_instance" "jumpbox" {
  compartment_id      = var.tenancy_ocid
  availability_domain = var.micro_availability_domain
  display_name        = "${var.project_name}-jumpbox"
  shape               = "VM.Standard.E2.1.Micro"

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    hostname_label   = "jumpbox"
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_x86.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gb
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  freeform_tags = {
    "role"    = "bastion"
    "project" = var.project_name
  }
}

# ============================================================
# web-victim — DVWA. No public IP. Ever.
# ============================================================
resource "oci_core_instance" "web_victim" {
  compartment_id      = var.tenancy_ocid
  availability_domain = var.micro_availability_domain
  display_name        = "${var.project_name}-web-victim"
  shape               = "VM.Standard.E2.1.Micro"

  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = false
    hostname_label   = "webvictim"
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_x86.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gb
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  freeform_tags = {
    "role"    = "victim"
    "project" = var.project_name
  }
}

# ============================================================
# soc-core — Wazuh + Prometheus + Grafana. ARM, capacity-gated.
# ============================================================
resource "oci_core_instance" "soc_core" {
  count = var.create_arm_instance ? 1 : 0

  compartment_id      = var.tenancy_ocid
  availability_domain = var.arm_availability_domain
  display_name        = "${var.project_name}-soc-core"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.arm_ocpus
    memory_in_gbs = var.arm_memory_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = false
    hostname_label   = "soccore"
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gb
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  freeform_tags = {
    "role"    = "siem"
    "project" = var.project_name
  }
}
