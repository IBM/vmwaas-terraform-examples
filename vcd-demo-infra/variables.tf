# Note. Generic variables. 

variable "vmwaas_user" {
  description = "vCloud Director username."
  default = ""
}

variable "vmwaas_password" {
  description = "vCloud Director instance password."
  default = ""
}

variable "vmwaas_api_token" {
  description = "vCloud Director API Token for user."
  default = ""
}

variable "vmwaas_org" {
  description = "vCloud Director organization name/id."
  default = ""
}

variable "vmwaas_url" {
  description = "vCloud Director url."
  default = ""
}

variable "vmwaas_vdc_name" {
  description = "vCloud Director virtual datacenter."
  default = ""
}

/*
variable "vmwaas_edge_gateway_name" {
  description = "vCloud Director virtual datacenter edge gateway name."
  default = ""
}
*/

variable "vmwaas_max_retry_timeout" {
  description = "Your vCloud Director retry timeout."
  default = 10
}

variable "vmwaas_allow_unverified_ssl" {
  description = "Allow unverified ssl."
  default = true
}

# Note. Use a common name prefix for each item. 

variable "item_name_prefix" {
  description = "Add a prefix for instance names."
  default = "test"
}


# Note. Create random password with terraform. If you select no, 
# Director will generate one for each Virtual Machine. 


variable "terraform_created_random_passwords" {
  description = "Create random password with terraform."
  default = true
}

# Note. IBM Cloud DNS servers listed here. 
# You may also use your own here. 


variable "dns_servers" {
  default = ["161.26.0.10","161.26.0.11"] 
}


# Note. Create virtual data center netoworks of type `routed` or
# Note. Create virtual data center networks of type `routed` or
# `isolated`. You can define one `static_ip_pool`and one
# `dhcp_ip_pool` for each.

variable "vdc_networks" {
  description = "VDC networks to create."
  type = any
  default = {
    application-network-1 = {
      description = "Application network 1"
      type = "routed"
      subnet = {
        cidr = "172.26.100.0/24"
        prefix_length = 24
        gateway = "172.26.100.1"
        static_ip_pool = {
          start_address = "172.26.100.10"
          end_address   = "172.26.100.100"
        }
        dhcp_ip_pool = {
          start_address = "172.26.100.101"
          end_address   = "172.26.100.199"
        }        
      }
    },
    db-network-1 = {
      description = "DB network 1"
      type = "routed"
      subnet = {
        cidr = "172.26.200.0/24"
        prefix_length = 24
        gateway = "172.26.200.1"
        static_ip_pool = {
          start_address = "172.26.200.10"
          end_address   = "172.26.200.100"
        }
        dhcp_ip_pool = {
          start_address = "172.26.200.101"
          end_address   = "172.26.200.199"
        }        
      }
    },
    isolated-network-1 = {
      description = "Isolated network 2"
      type = "isolated"
      subnet = {
        cidr = "172.18.200.0/24"
        prefix_length = 24
        gateway = "172.18.200.1"
        static_ip_pool = {
          start_address = "172.18.200.10"
          end_address   = "172.18.200.100"
        }
        dhcp_ip_pool = {} # leave empty for isolated network   
      }
    },
  }
}


# Note. Create virtual machines inside your virtual data center.
# You can define each one individually and attach multiple networks
# and disks. Individual disks are created for each additional disk.

# Note. Check the storage profile names and apply to your VMs / disks.
# If left empty, default profile is used.

variable "virtual_machines" {
  description = "Virtual machines to create."
  type = any
  default = {
    app-server-1 = {
      image = {
        catalog_name  = "Public Catalog"
        template_name = "RedHat-8-Template-Official"
      }
      memory          = 8192
      cpus            = 2
      cpu_hot_add_enabled = true
      memory_hot_add_enabled = true
      storage_profile = ""
      networks = {
        0 = {
          name = "application-network-1"
          ip_allocation_mode = "POOL"
          is_primary = true
          ip = ""
        },
      }
      disks = {
        0 = {
          name = "logDisk"
          size_in_mb = "100"
          bus_type = "SCSI"
          bus_sub_type = "VirtualSCSI"
          bus_number = 1
          unit_number = 0
          storage_profile = ""
        },
        1 = {
          name = "dataDisk"
          size_in_mb = "100"
          bus_type = "SCSI"
          bus_sub_type = "VirtualSCSI"
          bus_number = 1
          unit_number = 1
          storage_profile = ""
        }
      }
    },
    app-server-2 = {
      image = {
        catalog_name  = "Public Catalog"
        template_name = "RedHat-8-Template-Official"
      }
      memory        = 8192
      cpus          = 2
      cpu_hot_add_enabled = true
      memory_hot_add_enabled = true
      storage_profile = ""
      networks = {
        0 = {
          name = "application-network-1"
          ip_allocation_mode = "MANUAL"
          is_primary = true
          ip = "172.26.100.20"
        },
      },
      disks = {
        0 = {
          name = "logDisk"
          size_in_mb = "100"
          bus_type = "SCSI"
          bus_sub_type = "VirtualSCSI"
          bus_number = 1
          unit_number = 0
          storage_profile = ""
        },
      }
    },
    db-server-1 = {
      image = {
        catalog_name  = "Public Catalog"
        template_name = "RedHat-8-Template-Official"
      }
      memory        = 8192
      cpus          = 2
      cpu_hot_add_enabled = true
      memory_hot_add_enabled = true
      storage_profile = ""
      networks = {
        0 = {
          name = "db-network-1"
          ip_allocation_mode = "POOL"
          is_primary = true
          ip = ""
        },
      }
      disks = {}
    },
    jump-server-1 = {
      image = {
        catalog_name  = "Public Catalog"
        template_name = "Windows-2022-Template-Official"
      }
      memory        = 8192
      cpus          = 2
      cpu_hot_add_enabled = true
      memory_hot_add_enabled = true
      storage_profile = ""
      networks = {
        0 = {
          name = "application-network-1"
          ip_allocation_mode = "POOL"
          is_primary = true
          ip = ""
        },
      },
      disks = {}
    }
  }
}


# Note. Map of available 6 public IPs. You can use these names
# in NAT rules. Do not change the map's keys here.


variable "public_ips" {
  description = "Available public IPs."
  default = {
    public-ip-0 = {
      name = "public-ip-0"
      description = ""
    },
    public-ip-1 = {
      name = "public-ip-1" 
      description = ""
    },
    public-ip-2 = {
      name = "public-ip-2" 
      description = ""
    },
    public-ip-3 = {
      name = "public-ip-3" 
      description = ""
    },
    public-ip-4 = {
      name = "public-ip-4" 
      description = ""
    },
    public-ip-5 = {
      name = "public-ip-5" 
      description = ""
    },
  }
}



# Note. You can use `vdc_networks` or `virtual_machines` keys as 
# address_targets here. Terraform will pick the IP address of 
# the specific resource and use that in the actual NAT rule.

# Note. You can specify the desired actual public IP address 
# (`external_address`) in the rule, or you can use the 
# `external_address_target`, which will pick the IP 
# addresss from the allocated IP pool (`edge_gateway_allocated_ips`). 

# Note. Use Director UI to get the name for the Application
# profiles."

variable "nat_rules" {
  description = "NAT rules to create."
  type = any
  default = {
  /* examples only for NO_SNAT rule
    no-snat-to-ibm-cloud-166-9 = {
      rule_type   = "NO_SNAT"
      description = "NO_SNAT rule to application-network-1"
      external_address_target = ""
      external_address = ""  
      internal_address_target = "application-network-1"
      internal_address = ""
      snat_destination_address = "166.9.0.0/16"
      logging = false
      priority = 10
      enabled = true
    },
    no-snat-to-ibm-cloud-161-26 = {
      rule_type   = "NO_SNAT"
      description = "NO_SNAT rule to application-network-1"
      external_address_target = ""
      external_address = ""  
      internal_address_target = "application-network-1"
      internal_address = ""
      snat_destination_address = "161.26.0.0/16"
      logging = false
      priority = 10
      enabled = true
    },
*/
    dnat-to-app-1 = {
      rule_type   = "DNAT"
      description = "DNAT rule to app-server-1"
      external_address_target = "public-ip-1"
      external_address = "" 
      internal_address_target = "app-server-1"
      internal_address = ""
      dnat_external_port = ""
      app_port_profile = ""
      logging = false
      priority = 90
      enabled = true
    },
    dnat-to-jump-1 = {
      rule_type   = "DNAT"
      description = "DNAT rule to jump-server-1"
      external_address_target = "public-ip-2"
      external_address = "" 
      internal_address_target = "jump-server-1"
      internal_address = ""
      dnat_external_port = ""
      app_port_profile = "RDP"
      logging = false
      priority = 90
      enabled = true
    },
    snat-to-internet-1 = {
      rule_type = "SNAT"
      description = "SNAT rule to application-network-1"
      external_address_target = "public-ip-0"
      external_address = ""  
      internal_address_target = "application-network-1"
      internal_address = ""
      snat_destination_address = ""
      logging = false
      priority = 100
      enabled = true
    },    
    snat-to-internet-2 = {
      rule_type = "SNAT"
      description = "SNAT rule to db-network-1"
      external_address_target = "public-ip-0"
      external_address = ""  
      internal_address_target = "db-network-1"
      internal_address = ""
      snat_destination_address = ""
      logging = false
      priority = 100
      enabled = true
    },  
  }  
}


# Note. You need to create IP sets to be used in firewall rules.
# You can use the `public_ips` keys here as address_targets,
# but you can define IP sets using real IP addresses using a
# list `ip_addresses`.


variable "ip_sets" {
  description = "IP sets to create."
  type = any
  default = {
    ip-set-on-public-ip-0 = {
      description = "Public IP 0 - used for SNAT"
      ip_addresses = []
      address_target = "public-ip-0"
    },
    ip-set-on-public-ip-1 = {
      description = "Public IP 2 - used for DNAT to app-server-1"
      ip_addresses = []
      address_target = "public-ip-1"
    },
    ip-set-on-public-ip-2 = {
      description = "Public IP 2 - used for DNAT to jump-server-1"
      ip_addresses = []
      address_target = "public-ip-2"
    },
    ip-set-on-public-ip-3 = {
      description = "Public IP 3"
      ip_addresses = []
      address_target = "public-ip-3"
    },
    ip-set-on-public-ip-4 = {
      description = "Public IP 4"
      ip_addresses = []
      address_target = "public-ip-4"
    },
    ip-set-on-public-ip-5 = {
      description = "Public IP 5"
      ip_addresses = []
      address_target = "public-ip-5"
    },
    ip-set-on-premises-networks = {
      description = "On-premises networks"
      ip_addresses = ["172.16.0.0/16",]
      address_target = ""
    },
  }
}

# Note. You need to create Static Groups to be used in firewall rules.
# You can use `vdc_networks` as keys here.

variable "security_groups" {
  description = "Static Groups to create."
  type = any
  default = {
    sg-application-network-1 = {
      description = "Static Group for application-network-1"
      address_targets = ["application-network-1"]
    },
    sg-db-network-1 = {
      description = "Static Group for db-network-1"
      address_targets = ["db-network-1"]
    },
    sg-all-routed-networks = {
      description = "Static Group for all VDC networks"
      address_targets = ["application-network-1", "db-network-1"]
    },
  }
}

# Note. You can use `vdc_networks`, `nat_rules` (for DNAT) or
# `ip_sets` keys as sources or destinations here. Terraform 
# will pick the IP address of the specific resource and 
# use that in the actual rule.

# Note. Use "ALLOW or "DROP".

# Note. Use Director UI to get the name for the Application
# profiles."


variable "firewall_rules" {
  description = "Firewall rules to create."
  type = any
  default = {
    app-1-egress = {
        action  = "ALLOW"
        direction = "OUT"
        ip_protocol = "IPV4"
        destinations = []                                          # These refer to IP sets or Static Groups (vdc_networks)
        sources = ["sg-application-network-1", "sg-db-network-1"]  # These refer to IP sets or Static Groups (vdc_networks)
        system_app_ports = []
        logging = false
        enabled = true
    },
    dnat-to-app-1-ingress = {
        action  = "ALLOW"
        direction = "IN"
        ip_protocol = "IPV4"
        destinations = ["ip-set-on-public-ip-1"]                   # These refer to IP sets or Static Groups (vdc_networks)
        sources = []                                               # These refer to IP sets or Static Groups (vdc_networks)
        system_app_ports = ["SSH","HTTPS","ICMP ALL"]
        logging = false
        enabled = true
    },
    dnat-to-jump-1-ingress = {
        action  = "ALLOW"
        direction = "IN"
        ip_protocol = "IPV4"
        destinations = ["ip-set-on-public-ip-2"]                   # These refer to IP sets or Static Groups (vdc_networks)
        sources = []                                               # These refer to IP sets or Static Groups (vdc_networks)
        system_app_ports = ["RDP"]
        logging = false
        enabled = true
    },
  }
}

