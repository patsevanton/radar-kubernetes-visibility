# OpenCost: расчёт стоимости кластера по тарифам Yandex Cloud (₽).
# Метрики OpenCost скрейпит vmagent из vmks-стека и складывает в vmsingle,
# Radar на вкладке Cost детектит их автоматически (node_total_hourly_cost и др.).
# Установка — helm-командой (см. README), Terraform только генерирует values.

locals {
  opencost_fqdn = "opencost.${local.ingress_public_ip}.sslip.io"

  opencost_values = templatefile("${path.module}/opencost-values.yaml.tftpl", {
    opencost_fqdn = local.opencost_fqdn
  })
}

resource "local_file" "write_opencost_values" {
  content         = local.opencost_values
  filename        = "${path.module}/opencost-values.yaml"
  file_permission = "0644"
}

output "opencost_fqdn" {
  description = "URL OpenCost UI за ingress-nginx (http, TLS не настроен)"
  value       = "http://${local.opencost_fqdn}"
}
