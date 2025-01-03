
################################################################################
# This code block gets information about vdc and its edge gw
################################################################################

data "vcd_org" "org" {
  name = var.vmwaas_org
}

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
  owner_id = data.vcd_org_vdc.org_vdc.id  
}




locals {
  edge_gateway_name = data.vcd_nsxt_edgegateway.edge.name
  edge_gateway_id = data.vcd_nsxt_edgegateway.edge.id
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
# This code block allocates public IPs - floating IPs
################################################################################


data "vcd_ip_space" "ip_space" {
  name        = var.public_ip_space_name
}

resource "vcd_ip_space_ip_allocation" "public_floating_ip" {
  for_each    = var.public_ips

  org_id      = data.vcd_org.org.id
  ip_space_id = data.vcd_ip_space.ip_space.id
  type        = "FLOATING_IP"

  #usage_state = "USED_MANUAL"
  #description = "manually used floating IP"
}


locals {
  public_ips = { for k,v in var.public_ips : k => {
    ip_address = vcd_ip_space_ip_allocation.public_floating_ip[k].ip_address
    description= v.description
    } 
  }
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
    #unit_number = v.disk_key
    }
  }
}

resource "vcd_independent_disk" "virtual_machines_disk" {
  for_each               = local.virtual_machines_disks_map

  name                   = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  size_in_mb             = each.value.disk.size_in_mb
  bus_type               = each.value.disk.bus_type
  bus_sub_type           = each.value.disk.bus_sub_type
  storage_profile        = each.value.disk.storage_profile
}



################################################################################
# This code block captures catalog items and their IDs
################################################################################


data "vcd_resource_list" "list_of_catalogs" {
  name               = "list_of_catalogs"
  resource_type      = "vcd_catalog"
  list_mode          = "name_id"
  # name_id_separator  = ";"
}

locals {
  vcd_catalogs = { for k,v in data.vcd_resource_list.list_of_catalogs.list : split("  ", v)[0] => {id = split("  ", v)[1] }}
}

module "catalog_info" {
  source              = "./modules/catalog_template"
  for_each            = local.vcd_catalogs
  catalog_name        = each.key
  catalog_id          = each.value.id
}

locals {
   catalog_templates = { for k,v in module.catalog_info : k => {catalog_items = v.catalog_items}}
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

  name                   = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  vapp_template_id       = module.catalog_info[each.value.image.catalog_name].catalog_templates[each.value.image.template_name].id

  memory                 = each.value.memory
  cpus                   = each.value.cpus
  storage_profile        = each.value.storage_profile

  cpu_hot_add_enabled    = each.value.cpu_hot_add_enabled
  memory_hot_add_enabled = each.value.memory_hot_add_enabled

  dynamic "network" {
    for_each = each.value.networks

    content {
      type               = "org"
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
      unit_number = disk.value.disk.unit_number 
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
  
  name                     = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  rule_type                = each.value.rule_type
  description              = each.value.description

  firewall_match           = "MATCH_INTERNAL_ADDRESS"

  priority                 = each.value.priority
  enabled                  = each.value.enabled

  #external_address         = each.value.external_address != "" ? each.value.external_address : local.public_ips[each.value.external_address_target].ip_address
  external_address         = each.value.external_address != "" ? each.value.external_address : vcd_ip_space_ip_allocation.public_floating_ip[each.value.external_address_target].ip_address
  internal_address         = each.value.internal_address != "" ? each.value.internal_address : "${cidrhost("${vcd_network_routed_v2.routed_network[each.value.internal_address_target].gateway}/${vcd_network_routed_v2.routed_network[each.value.internal_address_target].prefix_length}", 0)}/${vcd_network_routed_v2.routed_network[each.value.internal_address_target].prefix_length}"

  snat_destination_address = each.value.snat_destination_address

  logging                  = each.value.logging
}


# Note. Use this for DNAT rules. 

resource "vcd_nsxt_nat_rule" "dnat_rules" {
  for_each                 = local.dnat_rules

  org                      = var.vmwaas_org
  edge_gateway_id          = local.edge_gateway_id
  
  name                     = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  rule_type                = each.value.rule_type
  description              = each.value.description

  firewall_match           = "MATCH_EXTERNAL_ADDRESS"

  priority                 = each.value.priority
  enabled                  = each.value.enabled

  #external_address         = each.value.external_address != "" ? each.value.external_address : local.public_ips[each.value.external_address_target].ip_address
  external_address         = each.value.external_address != "" ? each.value.external_address : vcd_ip_space_ip_allocation.public_floating_ip[each.value.external_address_target].ip_address
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
  
  name                     = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  rule_type                = each.value.rule_type
  description              = each.value.description

  firewall_match           = "MATCH_INTERNAL_ADDRESS"

  priority                 = each.value.priority
  enabled                  = each.value.enabled

  internal_address         = each.value.internal_address != "" ? each.value.internal_address : "${cidrhost("${vcd_network_routed_v2.routed_network[each.value.internal_address_target].gateway}/${vcd_network_routed_v2.routed_network[each.value.internal_address_target].prefix_length}", 0)}/${vcd_network_routed_v2.routed_network[each.value.internal_address_target].prefix_length}"
  snat_destination_address = each.value.snat_destination_address

  logging                  = each.value.logging
}


# Note. Use this for NO_DNAT rules. 

resource "vcd_nsxt_nat_rule" "no_dnat_rules" {
  for_each                 = local.no_dnat_rules

  org                      = var.vmwaas_org
  edge_gateway_id          = local.edge_gateway_id
  
  name                     = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  rule_type                = each.value.rule_type
  description              = each.value.description

  firewall_match           = "MATCH_EXTERNAL_ADDRESS"

  priority                 = each.value.priority
  enabled                  = each.value.enabled

  #external_address         = each.value.external_address != "" ? each.value.external_address : local.public_ips[each.value.external_address_target].ip_address
  external_address         = each.value.external_address != "" ? each.value.external_address : vcd_ip_space_ip_allocation.public_floating_ip[each.value.external_address_target].ip_address

  dnat_external_port       = each.value.dnat_external_port

  logging                  = each.value.logging
}

#/*

# This code block creates an output structure.

locals {
  created_snat_rules = { for k,v in vcd_nsxt_nat_rule.snat_rules : k => {
    rule_type = v.rule_type
    name = v.name
    external_address = v.external_address
    internal_address = v.internal_address
    snat_destination_address = v.snat_destination_address
    dnat_external_port = v.dnat_external_port
    priority = v.priority
    enabled = v.enabled
    }  
  }
  created_dnat_rules = { for k,v in vcd_nsxt_nat_rule.dnat_rules : k => {
    rule_type = v.rule_type
    name = v.name
    external_address = v.external_address
    internal_address = v.internal_address
    snat_destination_address = v.snat_destination_address
    dnat_external_port = v.dnat_external_port
    priority = v.priority
    enabled = v.enabled
    }  
  }
  created_no_snat_rules = { for k,v in vcd_nsxt_nat_rule.no_snat_rules : k => {
    rule_type = v.rule_type
    name = v.name
    external_address = v.external_address
    internal_address = v.internal_address
    snat_destination_address = v.snat_destination_address
    dnat_external_port = v.dnat_external_port
    priority = v.priority
    enabled = v.enabled
    }  
  }
  created_no_dnat_rules = { for k,v in vcd_nsxt_nat_rule.no_dnat_rules : k => {
    rule_type = v.rule_type
    name = v.name
    external_address = v.external_address
    internal_address = v.internal_address
    snat_destination_address = v.snat_destination_address
    dnat_external_port = v.dnat_external_port
    priority = v.priority
    enabled = v.enabled
    }  
  }

  created_nat_rules = merge(
    local.created_snat_rules,
    local.created_dnat_rules,
    local.created_no_snat_rules,
    local.created_no_dnat_rules,) 
}

#*/

################################################################################
# This code block creates security groups
################################################################################


locals {
  security_groups = { for k,v in var.security_groups : k => {    
    member_org_network_ids = [ for addrtarget_k in v.address_targets : vcd_network_routed_v2.routed_network[addrtarget_k].id ]
    org_networks = v.address_targets
    description = v.description
    }
  }
}


resource "vcd_nsxt_security_group" "security_group" {
  for_each                 = local.security_groups

  org                      = var.vmwaas_org
  edge_gateway_id          = local.edge_gateway_id
  
  name                     = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  description              = "Security Group for ${each.value.description}"
  member_org_network_ids   = each.value.member_org_network_ids

  depends_on = [
    vcd_network_routed_v2.routed_network,
  ]
}

locals {
  created_security_groups = local.security_groups
}

################################################################################
# This code block creates IP sets
################################################################################


locals {
  ip_sets = { for k,v in var.ip_sets : k => {
    ip_addresses = v.ip_addresses == [] ? [ for addrtarget_k,addrtarget_v in vcd_ip_space_ip_allocation.public_floating_ip : addrtarget_v.ip_address if addrtarget_k == v.address_target ] : v.ip_addresses
    description = v.description
    }
  }
}


#/*

resource "vcd_nsxt_ip_set" "ip_set" {
  for_each                 = local.ip_sets

  org                      = var.vmwaas_org
  edge_gateway_id          = local.edge_gateway_id

  name                     = var.item_name_prefix == "" ? each.key : "${var.item_name_prefix}-${each.key}"

  description              = each.value.description

  ip_addresses             = each.value.ip_addresses
}


locals {
  created_ip_sets = local.ip_sets
}

#*/

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
 
      name                 = var.item_name_prefix == "" ? rule.key : "${var.item_name_prefix}-${rule.key}"

      enabled              = rule.value.enabled

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

  depends_on = [
    vcd_network_routed_v2.routed_network,
    vcd_nsxt_ip_set.ip_set,
    vcd_nsxt_security_group.security_group
  ]
}


locals {
  created_fw_rules = {
    id = vcd_nsxt_firewall.firewall.id
    org = vcd_nsxt_firewall.firewall.org
    rule = [ for k,v in vcd_nsxt_firewall.firewall.rule : {
      name = v.name
      action = v.action
      direction = v.direction
      enabled = v.enabled
      ip_protocol = v.ip_protocol
      app_port_profiles = v.app_port_profile_ids == null  ? [] : flatten(
          [ for id in v.app_port_profile_ids : [ for app_k,app_v in data.vcd_nsxt_app_port_profile.system : app_k if app_v.id == id ]]
        )
      destinations = v.destination_ids == null ? [] : flatten(concat(
          [ for id in v.destination_ids : [ for ipset_k,ipset_v in vcd_nsxt_ip_set.ip_set : ipset_k if ipset_v.id == id ]],
          [ for id in v.destination_ids : [ for sg_k,sg_v in vcd_nsxt_security_group.security_group : sg_k if sg_v.id == id ]],
        ))
      sources = v.source_ids == null ? [] : flatten(concat(
          [ for id in v.source_ids : [ for ipset_k,ipset_v in vcd_nsxt_ip_set.ip_set : ipset_k if ipset_v.id == id ]],
          [ for id in v.source_ids : [ for sg_k,sg_v in vcd_nsxt_security_group.security_group : sg_k if sg_v.id == id ]],
        ))
      logging = v.logging
      }
    ]
  }
}

