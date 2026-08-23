output "jumpbox_public_ip" {
  description = "SSH entry point for the whole lab"
  value       = oci_core_instance.jumpbox.public_ip
}

output "jumpbox_private_ip" {
  value = oci_core_instance.jumpbox.private_ip
}

output "web_victim_private_ip" {
  description = "Reachable only via ProxyJump through the jumpbox"
  value       = oci_core_instance.web_victim.private_ip
}

output "soc_core_private_ip" {
  description = "null until ARM capacity is obtained"
  value       = try(oci_core_instance.soc_core[0].private_ip, null)
}

output "ssh_config_snippet" {
  description = "Append to ~/.ssh/config for transparent bastion access"
  value       = <<-EOT
    Host soc-jump
      HostName ${oci_core_instance.jumpbox.public_ip}
      User ubuntu
      IdentityFile ~/.ssh/soc_lab_ed25519

    Host soc-victim
      HostName ${oci_core_instance.web_victim.private_ip}
      User ubuntu
      IdentityFile ~/.ssh/soc_lab_ed25519
      ProxyJump soc-jump
  EOT
}
