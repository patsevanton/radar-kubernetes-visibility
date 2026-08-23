locals {
  folder_id  = var.folder_id
  network_id = yandex_vpc_network.radar.id

  subnet_b_id   = yandex_vpc_subnet.radar-b.id
  subnet_d_id   = yandex_vpc_subnet.radar-d.id
  subnet_e_id   = yandex_vpc_subnet.radar-e.id
  subnet_b_zone = yandex_vpc_subnet.radar-b.zone
  subnet_d_zone = yandex_vpc_subnet.radar-d.zone
  subnet_e_zone = yandex_vpc_subnet.radar-e.zone

  # Публичный IP балансировщика ingress-nginx. FQDN Radar формируется через sslip.io
  # из этого адреса (см. outputs в k8s.tf и helm-values.yaml).
  ingress_public_ip = yandex_vpc_address.addr.external_ipv4_address[0].address
  radar_fqdn        = "radar.${local.ingress_public_ip}.sslip.io"
}
