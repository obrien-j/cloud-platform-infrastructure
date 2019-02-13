#
# This is a redacted version of the upstream values.yaml file found here:
# https://github.com/helm/charts/blob/dea84cfd139f0e7bd7721abfa53e4853c1379c0a/stable/oauth2-proxy/values.yaml
#

config:
  clientID: "${client_id}"
  clientSecret: "${client_secret}"
  cookieSecret: "${cookie_secret}"
  # Custom configuration file: oauth2_proxy.cfg
  # configFile: |-
  #   pass_basic_auth = false
  #   pass_access_token = true
  configFile: ""

extraArgs:
  provider: oidc
  oidc-issuer-url: ${issuer_url}
  email-domain: "*"
  upstream: "${upstream}"
  http-address: "0.0.0.0:4180"
  skip-auth-regex: "${exclude_paths}"
  cookie-expire: "7h"

ingress:
  enabled: true
  path: /
  hosts:
    - "${hostname}"
  # annotations:
  #   kubernetes.io/ingress.class: nginx
  #   kubernetes.io/tls-acme: "true"

resources: {}
  # limits:
  #   cpu: 100m
  #   memory: 300Mi
  # requests:
  #   cpu: 100m
  #   memory: 300Mi
