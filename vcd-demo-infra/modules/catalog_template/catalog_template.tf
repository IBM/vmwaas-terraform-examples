

data "vcd_resource_list" "catalog_items" {
  name               = "list_of_catalog_items"
  resource_type      = "vcd_catalog_item"
  parent             = var.catalog_name
  list_mode          = "name"
}


output "catalog_items" {
  value = data.vcd_resource_list.catalog_items.list 
}


data "vcd_catalog_vapp_template" "catalog_templates" {
  for_each           = toset(data.vcd_resource_list.catalog_items.list)

  catalog_id         = var.catalog_id
  name               = each.key

}

output "catalog_templates" {
  value = data.vcd_catalog_vapp_template.catalog_templates
}



