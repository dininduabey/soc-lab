# ============================================================
# VCN — the private address space containing the entire lab
# ============================================================
resource "oci_core_vcn" "main" {
  compartment_id = var.tenancy_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.project_name}-vcn"
  dns_label      = "soclab"
}

# ============================================================
# Gateways
# ============================================================

# Bidirectional internet access — public subnet only
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-igw"
  enabled        = true
}

# Outbound-only internet access — private subnet
resource "oci_core_nat_gateway" "nat" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-nat"
}

# ============================================================
# Route tables
# ============================================================
resource "oci_core_route_table" "public" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-rt-public"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-rt-private"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat.id
  }
}

# ============================================================
# Security lists — stateful packet filtering
# ============================================================
resource "oci_core_security_list" "public" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-sl-public"

  # SSH from your workstation only
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.admin_cidr
    description = "SSH from admin workstation"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # Path MTU discovery — prevents silent hangs on large transfers
  ingress_security_rules {
    protocol    = "1" # ICMP
    source      = "0.0.0.0/0"
    description = "ICMP fragmentation needed"
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all outbound"
  }
}

resource "oci_core_security_list" "private" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-sl-private"

  # Everything inbound must originate inside the VCN
  ingress_security_rules {
    protocol    = "all"
    source      = var.vcn_cidr
    description = "Intra-VCN traffic only"
  }

  ingress_security_rules {
    protocol    = "1"
    source      = "0.0.0.0/0"
    description = "ICMP fragmentation needed"
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Outbound via NAT for package installs"
  }
}

# ============================================================
# Subnets
# ============================================================
resource "oci_core_subnet" "public" {
  compartment_id             = var.tenancy_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.public_subnet_cidr
  display_name               = "${var.project_name}-subnet-public"
  dns_label                  = "public"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_subnet" "private" {
  compartment_id             = var.tenancy_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.private_subnet_cidr
  display_name               = "${var.project_name}-subnet-private"
  dns_label                  = "private"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  prohibit_public_ip_on_vnic = true
}
