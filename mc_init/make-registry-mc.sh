#!/usr/bin/env bash

set -euo pipefail

HOST="${HOST:-bastion}"
CLUSTER="${CLUSTER:-ocp}"
DOMAIN="${DOMAIN:-example.com}"
OUTDIR="${OUTDIR:-.}"

mkdir -p "${OUTDIR}"

REGISTRY_CONF_B64="$(
cat <<EOF | base64 -w 0
[[registry]]
  prefix = ""
  location = "registry.access.redhat.com"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${HOST}.${CLUSTER}.${DOMAIN}:5000/registry.access.redhat.com"

[[registry]]
  prefix = ""
  location = "registry.redhat.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${HOST}.${CLUSTER}.${DOMAIN}:5000/registry.redhat.io"

[[registry]]
  prefix = ""
  location = "docker.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${HOST}.${CLUSTER}.${DOMAIN}:5000/docker.io"

[[registry]]
  prefix = ""
  location = "docker.elastic.co"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${HOST}.${CLUSTER}.${DOMAIN}:5000/docker.elastic.co"

[[registry]]
  prefix = ""
  location = "gcr.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${HOST}.${CLUSTER}.${DOMAIN}:5000/gcr.io"

[[registry]]
  prefix = ""
  location = "quay.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${HOST}.${CLUSTER}.${DOMAIN}:5000/quay.io"

[[registry]]
  prefix = ""
  location = "registry.k8s.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${HOST}.${CLUSTER}.${DOMAIN}:5000/registry.k8s.io"

[[registry]]
  prefix = ""
  location = "redhat-operator-index"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${HOST}.${CLUSTER}.${DOMAIN}:5000/redhat-operator-index"

[[registry]]
  prefix = ""
  location = "ghcr.io"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${HOST}.${CLUSTER}.${DOMAIN}:5000/ghcr.io"

[[registry]]
  prefix = ""
  location = "registry.connect.redhat.com"
  mirror-by-digest-only = false

  [[registry.mirror]]
    location = "${HOST}.${CLUSTER}.${DOMAIN}:5000/registry.connect.redhat.com"
EOF
)"

for ROLE in master worker; do
cat > "${OUTDIR}/99-${ROLE}-registries.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: ${ROLE}
  name: 99-${ROLE}-registries
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
      - path: /etc/containers/registries.conf.d/growin.registry.conf
        mode: 0644
        overwrite: true
        contents:
          source: data:text/plain;charset=utf-8;base64,${REGISTRY_CONF_B64}
EOF
done
