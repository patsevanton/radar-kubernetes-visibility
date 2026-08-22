locals {
  radar_values = templatefile("${path.module}/helm-values.yaml.tftpl", {
    radar_fqdn = local.radar_fqdn
  })
}

resource "local_file" "write_radar_values" {
  content         = local.radar_values
  filename        = "${path.module}/helm-values.yaml"
  file_permission = "0644"
}
