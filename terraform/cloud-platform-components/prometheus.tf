resource "helm_repository" "coreos" {
  name = "coreos"
  url  = "https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/"
}

resource "kubernetes_storage_class" "prometheus_storage" {
  metadata {
    name = "prometheus-storage"
  }

  storage_provisioner = "kubernetes.io/aws-ebs"

  parameters {
    type = "gp2"
  }
}

data "template_file" "prometheus_operator" {
  template = "${file("${path.module}/templates/prometheus-operator.yaml.tpl")}"
  vars     = {}
}

resource "helm_release" "prometheus_operator" {
  name          = "prometheus-operator"
  chart         = "prometheus-operator"
  repository    = "${helm_repository.coreos.metadata.0.name}"
  namespace     = "monitoring"
  recreate_pods = "true"

  values = [
    "${data.template_file.prometheus_operator.rendered}",
  ]

  depends_on = [
    "null_resource.deploy",
  ]

  lifecycle {
    ignore_changes = ["keyring"]
  }
}

resource "random_id" "username" {
  byte_length = 8
}

resource "random_id" "password" {
  byte_length = 8
}

data "template_file" "kube_prometheus" {
  template = "${file("${path.module}/templates/kube-prometheus.yaml.tpl")}"

  vars {
    alertmanager_ingress = "https://alertmanager.apps.${data.terraform_remote_state.cluster.cluster_domain_name}"
    grafana_ingress      = "grafana.apps.${data.terraform_remote_state.cluster.cluster_domain_name}"
    grafana_root         = "https://grafana.apps.${data.terraform_remote_state.cluster.cluster_domain_name}"
    pagerduty_config     = "${var.pagerduty_config}"
    slack_config         = "${var.slack_config}"
    promtheus_ingress    = "https://prometheus.apps.${data.terraform_remote_state.cluster.cluster_domain_name}"
    random_username      = "${random_id.username.hex}"
    random_password      = "${random_id.password.hex}"
  }
}

resource "helm_release" "kube_prometheus" {
  name          = "kube-prometheus"
  chart         = "kube-prometheus"
  repository    = "${helm_repository.coreos.metadata.0.name}"
  namespace     = "monitoring"
  recreate_pods = "true"

  values = [
    "${data.template_file.kube_prometheus.rendered}",
  ]

  depends_on = [
    "null_resource.deploy",
    "helm_release.prometheus_operator",
  ]

  lifecycle {
    ignore_changes = ["keyring"]
  }
}

# Alertmanager and Prometheus proxy

resource "random_id" "session_secret" {
  byte_length = 16
}

resource "auth0_client" "monitoring" {
  name        = "monitoring.${data.terraform_remote_state.cluster.cluster_domain_name}"
  description = "monitoring auth proxy"
  app_type    = "regular_web"

  callbacks = [
    "https://prometheus.apps.${data.terraform_remote_state.cluster.cluster_domain_name}/oauth2/callback",
    "https://alertmanager.apps.${data.terraform_remote_state.cluster.cluster_domain_name}/oauth2/callback",
  ]

  custom_login_page_on = true
  is_first_party       = true
  oidc_conformant      = true
  sso                  = true

  jwt_configuration = {
    alg                 = "RS256"
    lifetime_in_seconds = "36000"
  }
}

data "template_file" "prometheus-proxy" {
  template = "${file("${path.module}/templates/oauth2-proxy.yaml.tpl")}"

  vars {
    upstream      = "http://kube-prometheus:9090"
    hostname      = "prometheus.apps.${data.terraform_remote_state.cluster.cluster_domain_name}"
    exclude_paths = "^/-/healthy$"
    issuer_url    = "${data.terraform_remote_state.cluster.oidc_issuer_url}"
    client_id     = "${auth0_client.monitoring.client_id}"
    client_secret = "${auth0_client.monitoring.client_secret}"
    cookie_secret = "${random_id.session_secret.b64_std}"
  }
}

resource "helm_release" "prometheus-proxy" {
  name          = "prometheus-proxy"
  namespace     = "monitoring"
  chart         = "stable/oauth2-proxy"
  version       = "0.9.1"
  recreate_pods = true

  values = [
    "${data.template_file.prometheus-proxy.rendered}",
  ]

  depends_on = [
    "null_resource.deploy",
    "random_id.session_secret",
  ]

  lifecycle {
    ignore_changes = ["keyring"]
  }
}

data "template_file" "alertmanager-proxy" {
  template = "${file("${path.module}/templates/oauth2-proxy.yaml.tpl")}"

  vars {
    upstream      = "http://kube-prometheus-alertmanager:9093"
    hostname      = "alertmanager.apps.${data.terraform_remote_state.cluster.cluster_domain_name}"
    exclude_paths = "^/-/healthy$"
    issuer_url    = "${data.terraform_remote_state.cluster.oidc_issuer_url}"
    client_id     = "${auth0_client.monitoring.client_id}"
    client_secret = "${auth0_client.monitoring.client_secret}"
    cookie_secret = "${random_id.session_secret.b64_std}"
  }
}

resource "helm_release" "alertmanager-proxy" {
  name          = "alertmanager-proxy"
  namespace     = "monitoring"
  chart         = "stable/oauth2-proxy"
  version       = "0.9.1"
  recreate_pods = true

  values = [
    "${data.template_file.alertmanager-proxy.rendered}",
  ]

  depends_on = [
    "null_resource.deploy",
    "random_id.session_secret",
  ]

  lifecycle {
    ignore_changes = ["keyring"]
  }
}
