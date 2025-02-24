locals {
  container_networks = {
    services = var.networks.services
  }

  container_files = {
    "/config/coredns/Corefile"         = "${path.root}/files/coredns/Corefile.tftpl"
    "/config/coredns/hosts"            = "${path.root}/files/coredns/hosts.tftpl"
    "/config/dnsdist/dnsdist.conf"     = "${path.root}/files/dnsdist/dnsdist.conf.tftpl"
    "/config/haproxy/haproxy.cfg"      = "${path.root}/files/haproxy/haproxy.cfg.tftpl"
    "/config/vector-agent/vector.yaml" = "${path.root}/files/vector-agent/vector.yaml.tftpl"
  }
}

resource "vyos_config" "container_networks" {
  for_each = local.container_networks
  path     = "container network ${each.key}"
  value = jsonencode({
    "prefix" = "${each.value}"
  })
}

resource "remote_file" "container_files" {
  for_each = local.container_files
  provider = remote
  path     = each.key
  content = templatefile(
    pathexpand(each.value),
    {
      address_book = var.address_book,
      config       = var.config
      networks     = var.networks
    }
  )
  permissions = "0775"
  owner       = "0"   # root
  group       = "104" # vyattacfg
}

resource "vyos_config" "container_name" {
  path = "container name"
  value = jsonencode(merge(
    # CoreDNS
    {
      "vyos-coredns" = {
        "cap-add" = "net-bind-service"
        "image"   = "${var.config.containers.coredns.image}"
        "memory"  = "0"
        "network" = {
          "services" = {
            "address" = "${cidrhost(var.networks.services, 3)}"
          }
        }
        "restart"       = "on-failure"
        "shared-memory" = "0"
        "volume" = {
          "config" = {
            "source"      = "/config/coredns"
            "destination" = "/config"
          }
        }
      }
    },

    # dnsdist
    {
      "dnsdist" = {
        "cap-add" = "net-bind-service"
        "image"   = "${var.config.containers.dnsdist.image}"
        "memory"  = "0"
        "environment" = {
          "TZ" = { "value" = "Europe/Amsterdam" }
        }
        "network" = {
          "services" = {
            "address" = "${cidrhost(var.networks.services, 4)}"
          }
        }
        "restart"       = "on-failure"
        "shared-memory" = "0"
        "volume" = {
          "config" = {
            "destination" = "/etc/dnsdist/dnsdist.conf"
            "source"      = "/config/dnsdist/dnsdist.conf"
          }
        }
      }
    },

    # haproxy
    {
      "haproxy-k8s-api" = {
        "image"  = "${var.config.containers.haproxy.image}"
        "memory" = "0"
        "network" = {
          "services" = {
            "address" = "${cidrhost(var.networks.services, 2)}"
          }
        }
        "restart"       = "on-failure"
        "shared-memory" = "0"
        "volume" = {
          "config" = {
            "source"      = "/config/haproxy/haproxy.cfg"
            "destination" = "/usr/local/etc/haproxy/haproxy.cfg"
          }
        }
      }
    },

    # node-exporter
    {
      "node-exporter" = {
        "image"  = "${var.config.containers.node-exporter.image}"
        "memory" = "0"
        "network" = {
          "services" = {
            "address" = "${cidrhost(var.networks.services, 7)}"
          }
        }
        "environment" = {
          "procfs" = { "value" = "/host/proc" }
          "rootfs" = { "value" = "/host/rootfs" }
          "sysfs"  = { "value" = "/host/sys" }
        }
        "restart"       = "on-failure"
        "shared-memory" = "0"
        "volume" = {
          "procfs" = {
            "source"      = "/proc"
            "destination" = "/host/proc"
            "mode"        = "ro"
          }
          "rootfs" = {
            "source"      = "/"
            "destination" = "/host/rootfs"
            "mode"        = "ro"
          }
          "sysfs" = {
            "source"      = "/sys"
            "destination" = "/host/sys"
            "mode"        = "ro"
          }
        }
      }
    },

    # speedtest-exporter
    {
      "speedtest-exporter" = {
        "image"  = "${var.config.containers.speedtest-exporter.image}"
        "memory" = "0"
        "network" = {
          "services" = {
            "address" = "${cidrhost(var.networks.services, 8)}"
          }
        }
        "restart"       = "on-failure"
        "shared-memory" = "0"
      }
    },

    # udp-broadcast-relay-sonos
    {
      "udp-broadcast-relay-sonos" = {
        "cap-add"             = "net-raw"
        "image"               = "${var.config.containers.udp-broadcast-relay.image}"
        "memory"              = "0"
        "allow-host-networks" = {}
        "environment" = {
          "CFG_ID"        = { "value" = "1" }
          "CFG_PORT"      = { "value" = "1900" }
          "CFG_DEV"       = { "value" = "${var.config.zones.trusted.interface};${var.config.zones.iot.interface}" }
          "CFG_MULTICAST" = { "value" = "239.255.255.250" }
          "SEPARATOR"     = { "value" = ";" }
        }
        "restart"       = "on-failure"
        "shared-memory" = "0"
      }
    },

    # udp-broadcast-relay-mdns
    {
      "udp-broadcast-relay-mdns" = {
        "cap-add"             = "net-raw"
        "image"               = "${var.config.containers.udp-broadcast-relay.image}"
        "memory"              = "0"
        "allow-host-networks" = {}
        "environment" = {
          "CFG_ID"        = { "value" = "2" }
          "CFG_PORT"      = { "value" = "5353" }
          "CFG_DEV"       = { "value" = "${var.config.zones.trusted.interface};${var.config.zones.iot.interface}" }
          "CFG_MULTICAST" = { "value" = "224.0.0.251" }
          "SEPARATOR"     = { "value" = ";" }
        }
        "restart"       = "on-failure"
        "shared-memory" = "0"
      }
    },

    # unifi
    {
      "unifi" = {
        "image"  = "${var.config.containers.unifi.image}"
        "memory" = "0"
        "network" = {
          "services" = {
            "address" = "${cidrhost(var.networks.services, 10)}"
          }
        }
        "environment" = {
          "RUNAS_UID0"   = { "value" = "false" }
          "UNIFI_UID"    = { "value" = "999" }
          "UNIFI_GID"    = { "value" = "999" }
          "UNIFI_STDOUT" = { "value" = "true" }
          "TZ"           = { "value" = "Europe/Amsterdam" }
        }
        "restart"       = "on-failure"
        "shared-memory" = "0"
        "volume" = {
          "data" = {
            "source"      = "/config/unifi/data"
            "destination" = "/unifi"
          }
        }
      }
    },

    # vector-agent
    {
      "vector-agent" = {
        "image"  = "${var.config.containers.vector.image}"
        "memory" = "0"
        "network" = {
          "services" = {
            "address" = "${cidrhost(var.networks.services, 9)}"
          }
        }
        "environment" = {
          "VECTOR_CONFIG"       = { "value" = "/etc/vector/vector.yaml" }
          "VECTOR_WATCH_CONFIG" = { "value" = "true" }
        }
        "restart"       = "on-failure"
        "shared-memory" = "0"
        "volume" = {
          "config" = {
            "source"      = "/config/vector-agent/vector.yaml"
            "destination" = "/etc/vector/vector.yaml"
          }
          "data" = {
            "source"      = "/config/vector-agent/data"
            "destination" = "/var/lib/vector"
          }
          "logs" = {
            "source"      = "/var/log"
            "destination" = "/var/log"
            "mode"        = "ro"
          }
        }
      }
    },
  ))

  depends_on = [
    vyos_config.container_networks,
    remote_file.container_files,
  ]
}
