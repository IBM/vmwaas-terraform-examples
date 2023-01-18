
################################################################################
# This code block gets information about vdc and its edge gw
################################################################################


data "vcd_resource_list" "list_of_vdcs" {
  name =  "list_of_vdcs"
  resource_type = "vcd_org_vdc"
  list_mode = "name"
}

data "vcd_org_vdc" "org_vdc" {
  name = var.vmwaas_vdc_name
}

data "vcd_resource_list" "list_of_vdc_edges" {
  name =  "list_of_vdc_edges"
  resource_type = "vcd_nsxt_edgegateway"
  list_mode = "name"
  vdc = var.vmwaas_vdc_name         # Filter per VDC name
}

data "vcd_nsxt_edgegateway" "edge" {
  #name = var.vmwaas_edge_gateway_name
  name = data.vcd_resource_list.list_of_vdc_edges.list[0]
  # vdc = var.vmwaas_vdc_name
  owner_id = data.vcd_org_vdc.org_vdc.id  
}



locals {
  edge_gateway_name = data.vcd_nsxt_edgegateway.edge.name
  edge_gateway_id = data.vcd_nsxt_edgegateway.edge.id
  edge_gateway_primary_ip = data.vcd_nsxt_edgegateway.edge.primary_ip
  edge_gateway_prefix_length = tolist(data.vcd_nsxt_edgegateway.edge.subnet)[0].prefix_length
  edge_gateway_gateway = tolist(data.vcd_nsxt_edgegateway.edge.subnet)[0].gateway
  edge_gateway_allocated_ips_start_address = tolist(tolist(data.vcd_nsxt_edgegateway.edge.subnet)[0].allocated_ips)[0].start_address
  edge_gateway_allocated_ips_end_address = tolist(tolist(data.vcd_nsxt_edgegateway.edge.subnet)[0].allocated_ips)[0].end_address  
}


locals {
  public_ips = { for k,v in var.public_ips : v.name => {
    ip_address = cidrhost("${local.edge_gateway_gateway}/${local.edge_gateway_prefix_length}", k+2)
    description= v.description
    } 
  }
}




################################################################################
# This code block creates virtual data center network resources
################################################################################

locals {
  vdc_networks_routed = {
    for k, v in var.vdc_networks : k => v if v.type == "routed"
  }
  vdc_networks_isolated = {
    for k, v in var.vdc_networks : k => v if v.type == "isolated"
  }
}

resource "vcd_network_routed_v2" "routed_network" {
  for_each = local.vdc_networks_routed

  #name            = each.key item_name_prefix
  name            = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"
  description     = each.value.description

  edge_gateway_id = local.edge_gateway_id
  gateway         = each.value.subnet.gateway
  prefix_length   = each.value.subnet.prefix_length

  static_ip_pool {
    start_address = each.value.subnet.static_ip_pool.start_address
    end_address   = each.value.subnet.static_ip_pool.end_address
  }

  dns1            = var.dns_servers[0]
  dns2            = var.dns_servers[1]
}


resource "vcd_network_isolated_v2" "isolated_network" {
  for_each = local.vdc_networks_isolated


  #name            = each.key
  name            = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"
  description     = each.value.description

  gateway         = each.value.subnet.gateway
  prefix_length   = each.value.subnet.prefix_length

  static_ip_pool {
    start_address = each.value.subnet.static_ip_pool.start_address
    end_address   = each.value.subnet.static_ip_pool.end_address
  }
}


resource "vcd_nsxt_network_dhcp" "dhcp_pool" {
  for_each        = local.vdc_networks_routed

  org_network_id  = vcd_network_routed_v2.routed_network[each.key].id

  pool {
    start_address = each.value.subnet.dhcp_ip_pool.start_address
    end_address   = each.value.subnet.dhcp_ip_pool.end_address
  }

}


locals {
  created_vdc_networks_routed = {
    for k, v in vcd_network_routed_v2.routed_network : k => {
      name = v.name
      gateway = "${v.gateway}/${v.prefix_length}"
      #static_ip_pool = v.static_ip_pool
      id = v.id
      type = "routed"
    }
  }
  created_vdc_networks_isolated = {
    for k, v in vcd_network_isolated_v2.isolated_network : k => {
      name = v.name
      gateway = "${v.gateway}/${v.prefix_length}"
      #static_ip_pool = v.static_ip_pool
      id = v.id
      type = "isolated"
    }
  }
  created_vdc_networks = merge(local.created_vdc_networks_routed,local.created_vdc_networks_isolated)
}


################################################################################
# This code block creates virtual machine disks
################################################################################


locals {
  virtual_machines_disks_list = flatten([ for k,v in var.virtual_machines : [
    for disks_key,disks_values in v.disks : { 
      virtual_machine = k
      disk_key = disks_key
      disk = disks_values
      }
    ] 
  ])
  virtual_machines_disks_map = { for k,v in local.virtual_machines_disks_list : "${v.virtual_machine}-disk-${v.disk_key}-${v.disk.name}" => { 
    virtual_machine = "${v.virtual_machine}"
    disk = v.disk
    unit_number = v.disk_key
    }
  }
}

resource "vcd_independent_disk" "virtual_machines_disk" {
  for_each               = local.virtual_machines_disks_map

  #name                   = each.key
  name                   = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  size_in_mb             = each.value.disk.size_in_mb
  bus_type               = each.value.disk.bus_type
  bus_sub_type           = each.value.disk.bus_sub_type
  storage_profile        = each.value.disk.storage_profile
}



################################################################################
# This code block captures catalog items and their IDs
################################################################################



data "vcd_resource_list" "list_of_catalog_items" {
  name               = "list_of_catalog_items"
  resource_type      = "vcd_catalog_item"
  parent             = "Public Catalog"
  list_mode          = "name"
}

output "public_catalog_items" {
  value = data.vcd_resource_list.list_of_catalog_items.list
}



################################################################################
# This code block creates virtual machines
################################################################################

resource "random_string" "admin_password" {
  for_each               = var.terraform_created_random_passwords == true ? var.virtual_machines : {}

  length                 = 16
  special                = true
  numeric                = true
  min_special            = 1
  min_lower              = 2
  min_numeric            = 2
  min_upper              = 2
  override_special      = "@!#%"
}



resource "vcd_vm" "virtual_machines" {
  for_each               = var.virtual_machines

  #name                   = each.key
  name                   = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"


  catalog_name           = each.value.image.catalog_name
  template_name          = each.value.image.template_name

  #vapp_template_id       = data.vcd_catalog_vapp_template[each.value.image.template_name].id


  memory                 = each.value.memory
  cpus                   = each.value.cpus
  storage_profile        = each.value.storage_profile

  cpu_hot_add_enabled    = each.value.cpu_hot_add_enabled
  memory_hot_add_enabled = each.value.memory_hot_add_enabled

  dynamic "network" {
    for_each = each.value.networks

    content {
      type               = "org"
      #name               = vcd_network_routed_v2.routed_network[network.value.name].name
      name               = local.created_vdc_networks[network.value.name].type == "routed" ? vcd_network_routed_v2.routed_network[network.value.name].name : vcd_network_isolated_v2.isolated_network[network.value.name].name
      ip_allocation_mode = network.value.ip_allocation_mode
      is_primary         = network.value.is_primary
      ip                 = network.value.ip_allocation_mode == "MANUAL" ? network.value.ip : ""
    }
  }

  dynamic "disk" {
    for_each = { for k,v in local.virtual_machines_disks_map : k => v if v.virtual_machine == each.key }

    content {
      name        = vcd_independent_disk.virtual_machines_disk["${disk.key}"].name
      bus_number  = disk.value.disk.bus_number
      unit_number = disk.value.unit_number 
    }
  }

  customization {
    auto_generate_password              = var.terraform_created_random_passwords == true ? false : true
    admin_password                      = var.terraform_created_random_passwords == true ? random_string.admin_password[each.key].result : ""
    must_change_password_on_first_login = false    
  }
}

locals {
  virtual_machines = {
    for k, v in vcd_vm.virtual_machines : k => {
      name               = v.name
      admin_password     = nonsensitive(v.customization[0].admin_password)
      network            = [ for network in v.network : {
        name             = network.name
        ip_address       = network.ip
        is_primary       = network.is_primary
        }
      ]

    }
  }
}




################################################################################
# This code block creates NAT rules
################################################################################


locals {
  snat_rules = {
    for k, v in var.nat_rules : k => v if v.rule_type == "SNAT"
  }
  dnat_rules = {
    for k, v in var.nat_rules : k => v if v.rule_type == "DNAT"
  }
  no_snat_rules = {
    for k, v in var.nat_rules : k => v if v.rule_type == "NO_SNAT"
  }
  no_dnat_rules = {
    for k, v in var.nat_rules : k => v if v.rule_type == "NO_DNAT"
  }
}

# Note. Use this for SNAT rules. 

resource "vcd_nsxt_nat_rule" "snat_rules" {
  for_each                 = local.snat_rules

  org                      = var.vmwaas_org
  edge_gateway_id          = local.edge_gateway_id
  
  #name                     = each.key
  name                     = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  rule_type                = each.value.rule_type
  description              = each.value.description

  firewall_match           = "MATCH_INTERNAL_ADDRESS"

  #external_address         = each.value.external_address != "" ? each.value.external_address : cidrhost("${local.edge_gateway_gateway}/${local.edge_gateway_prefix_length}", each.value.external_address_list_index+2)
  external_address         = each.value.external_address != "" ? each.value.external_address : local.public_ips[each.value.external_address_target].ip_address
  #internal_address         = each.value.internal_address != "" ? each.value.internal_address : cidrhost("${vcd_network_routed_v2.routed_network[each.value.internal_address_target].gateway}/${vcd_network_routed_v2.routed_network[each.value.internal_address_target].prefix_length}", 0)
  internal_address         = each.value.internal_address != "" ? each.value.internal_address : "${cidrhost("${vcd_network_routed_v2.routed_network[each.value.internal_address_target].gateway}/${vcd_network_routed_v2.routed_network[each.value.internal_address_target].prefix_length}", 0)}/${vcd_network_routed_v2.routed_network[each.value.internal_address_target].prefix_length}"

  snat_destination_address = each.value.snat_destination_address

  logging                  = each.value.logging
}

# Note. Use this for DNAT rules. 

resource "vcd_nsxt_nat_rule" "dnat_rules" {
  for_each                 = local.dnat_rules

  org                      = var.vmwaas_org
  edge_gateway_id          = local.edge_gateway_id
  
  #name                     = each.key
  name                     = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  rule_type                = each.value.rule_type
  description              = each.value.description

  firewall_match           = "MATCH_EXTERNAL_ADDRESS"

  #external_address         = cidrhost("${local.edge_gateway_gateway}/${local.edge_gateway_prefix_length}", each.value.external_address_list_index+2)
  external_address         = each.value.external_address != "" ? each.value.external_address : local.public_ips[each.value.external_address_target].ip_address
  internal_address         = each.value.internal_address != "" ? each.value.internal_address : [for k, v in vcd_vm.virtual_machines[each.value.internal_address_target].network : v.ip if v.is_primary == true ][0]

  dnat_external_port       = each.value.dnat_external_port
  app_port_profile_id      = each.value.app_port_profile != "" ? data.vcd_nsxt_app_port_profile.system[each.value.app_port_profile].id : ""

  logging                  = each.value.logging
}

# Note. Use this for NO_SNAT rules. 

resource "vcd_nsxt_nat_rule" "no_snat_rules" {
  for_each                 = local.no_snat_rules

  org                      = var.vmwaas_org
  edge_gateway_id          = local.edge_gateway_id
  
  #name                     = each.key
  name                     = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  rule_type                = each.value.rule_type
  description              = each.value.description

  firewall_match           = "MATCH_INTERNAL_ADDRESS"

  #internal_address         = each.value.internal_address != "" ? each.value.internal_address : cidrhost("${vcd_network_routed_v2.routed_network[each.value.internal_address_target].gateway}/${vcd_network_routed_v2.routed_network[each.value.internal_address_target].prefix_length}", 0)
  internal_address         = each.value.internal_address != "" ? each.value.internal_address : "${cidrhost("${vcd_network_routed_v2.routed_network[each.value.internal_address_target].gateway}/${vcd_network_routed_v2.routed_network[each.value.internal_address_target].prefix_length}", 0)}/${vcd_network_routed_v2.routed_network[each.value.internal_address_target].prefix_length}"
  snat_destination_address = each.value.snat_destination_address

  logging                  = each.value.logging
}

### test starts - make the above to support both routed network as well as virtual machines as internal_address keys
/*
locals {
  #test_key = "sami-demo-application-network-1"
  test_key = "app-server-1"

  test = element(concat(
          [for k,v in vcd_network_routed_v2.routed_network : "${vcd_network_routed_v2.routed_network[k].gateway}" if k == local.test_key],
          [for k,v in vcd_vm.virtual_machines : v.network[0].ip if k == local.test_key]
          ),0)
}
*/
### test ends






# Note. Use this for NO_DNAT rules. 

resource "vcd_nsxt_nat_rule" "no_dnat_rules" {
  for_each                 = local.no_dnat_rules

  org                      = var.vmwaas_org
  edge_gateway_id          = local.edge_gateway_id
  
  #name                     = each.key
  name                     = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  rule_type                = each.value.rule_type
  description              = each.value.description

  firewall_match           = "MATCH_EXTERNAL_ADDRESS"

  #external_address         = cidrhost("${local.edge_gateway_gateway}/${local.edge_gateway_prefix_length}", each.value.external_address_list_index+2)
  external_address         = each.value.external_address != "" ? each.value.external_address : local.public_ips[each.value.external_address_target].ip_address

  dnat_external_port       = each.value.dnat_external_port

  logging                  = each.value.logging
}



# This code block creates an output structure.

locals {
  created_snat_rules = { for k,v in vcd_nsxt_nat_rule.snat_rules : k => {
    rule_type = v.rule_type
    name = v.name
    external_address = v.external_address
    internal_address = v.internal_address
    snat_destination_address = v.snat_destination_address
    dnat_external_port = v.dnat_external_port
    }  
  }
  created_dnat_rules = { for k,v in vcd_nsxt_nat_rule.dnat_rules : k => {
    rule_type = v.rule_type
    name = v.name
    external_address = v.external_address
    internal_address = v.internal_address
    snat_destination_address = v.snat_destination_address
    dnat_external_port = v.dnat_external_port
    }  
  }
  created_no_snat_rules = { for k,v in vcd_nsxt_nat_rule.no_snat_rules : k => {
    rule_type = v.rule_type
    name = v.name
    external_address = v.external_address
    internal_address = v.internal_address
    snat_destination_address = v.snat_destination_address
    dnat_external_port = v.dnat_external_port
    }  
  }
  created_no_dnat_rules = { for k,v in vcd_nsxt_nat_rule.no_dnat_rules : k => {
    rule_type = v.rule_type
    name = v.name
    external_address = v.external_address
    internal_address = v.internal_address
    snat_destination_address = v.snat_destination_address
    dnat_external_port = v.dnat_external_port
    }  
  }

  created_nat_rules = merge(
    local.created_snat_rules,
    local.created_dnat_rules,
    local.created_no_snat_rules,
    local.created_no_dnat_rules,) 
}



################################################################################
# This code block creates security groups
################################################################################

locals {
  all_org_vdc_routed_networks = { 
    all-org-vdc-routed-networks = {
      member_org_network_ids = [for k,v in var.vdc_networks : vcd_network_routed_v2.routed_network[k].id if v.type == "routed"]
      description = "All routed networks"
    }
  }
  org_vdc_routed_networks = {for k,v in var.vdc_networks : k => { 
      member_org_network_ids = [vcd_network_routed_v2.routed_network[k].id]
      description = v.description
    } if v.type == "routed"
  }
  security_groups = merge(local.all_org_vdc_routed_networks,local.org_vdc_routed_networks)
}


resource "vcd_nsxt_security_group" "security_group" {
  for_each                 = local.security_groups

  org                      = var.vmwaas_org
  edge_gateway_id          = local.edge_gateway_id
  
  #name                     = each.key
  name                     = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  description              = "Security Group for ${each.value.description}"
  member_org_network_ids   = each.value.member_org_network_ids
}



################################################################################
# This code block creates IP sets
################################################################################


# Note. Creates IP sets for used public IPs and for the IP sets defined 
# in the variable, such as on-premises networks.  


locals {
  public_ip_set = { for k,v in var.nat_rules : k => {
    #ip_addresses = [ cidrhost("${local.edge_gateway_gateway}/${local.edge_gateway_prefix_length}", v.external_address_list_index+2) ]
    ip_addresses = [ v.external_address != "" ? v.external_address : local.public_ips[v.external_address_target].ip_address ]
    description = "Public IP of ${v.description}"
    } if v.rule_type == "SNAT" || v.rule_type == "DNAT"
  }
  other_ip_set = { for k,v in var.ip_sets : k => {
    ip_addresses = v.ip_addresses
    description = v.description
    }
  }
  ip_sets = merge(local.public_ip_set,local.other_ip_set)
}


resource "vcd_nsxt_ip_set" "ip_set" {
  for_each                 = local.ip_sets

  org                      = var.vmwaas_org
  edge_gateway_id          = local.edge_gateway_id

  #name                     = each.key
  name                     = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  description              = each.value.description

  ip_addresses             = each.value.ip_addresses
}



################################################################################
# This code block collects required Application Port Profile IDs 
################################################################################

# Note. Collects system Application Port Profile IDs for profles used in 
# specified FW rules. 

locals {
  system_app_ports_list_nat = compact([for k,v in var.nat_rules : v.app_port_profile if v.rule_type=="DNAT"])
  system_app_ports_list_fw = flatten([for k,v in var.firewall_rules : v.system_app_ports])
  system_app_ports_list = distinct(concat(local.system_app_ports_list_nat, local.system_app_ports_list_fw))
  system_app_ports_map = { for k in local.system_app_ports_list : k => { 
    name = k
    }
  }
}


data "vcd_nsxt_app_port_profile" "system" {
  for_each =  local.system_app_ports_map
  scope = "SYSTEM"
  name = each.value.name
}



################################################################################
# This code block creates firewall rules
################################################################################

# Note. You can use `vdc_networks`, `nat_rules` (for DNAT) or
# `ip_sets` keys as sources or destinations here. Terraform 
# will pick the IP address of the specific resource and 
# use that in the actual rule.

# Note. Use "ALLOW or "DROP".

# Note. Use Director UI to get the name for the Application
# profiles."

resource "vcd_nsxt_firewall" "firewall" {
  org = var.vmwaas_org
  edge_gateway_id = local.edge_gateway_id

  dynamic "rule" {
    for_each = var.firewall_rules
    content {
      action               = rule.value.action
 
      #name                 = rule.key
      name                 = var.item_name_prefix == "" ? rule.key : "${var.item_name_prefix}-${rule.key}"

      direction            = rule.value.direction
      ip_protocol          = rule.value.ip_protocol
      source_ids           = concat(
          [for k,v in vcd_nsxt_ip_set.ip_set : v.id if contains(rule.value.sources,k)],
          [for k,v in vcd_nsxt_security_group.security_group : v.id if contains(rule.value.sources,k)]
          )
      destination_ids      = concat(
          [for k,v in vcd_nsxt_ip_set.ip_set : v.id if contains(rule.value.destinations,k)],
          [for k,v in vcd_nsxt_security_group.security_group : v.id if contains(rule.value.destinations,k)]
          )
      app_port_profile_ids = [for k in rule.value.system_app_ports : data.vcd_nsxt_app_port_profile.system[k].id]

      logging              = rule.value.logging
    }
  }
}




locals {
  created_fw_rules = vcd_nsxt_firewall.firewall
  }

output "created_fw_rules" {
  value = local.created_fw_rules
}

#*/
