################################################################################
# This code block defines terraform and provider details
################################################################################

terraform {
  required_providers {
    vcd = {
      source = "vmware/vcd"
    }
  }
  required_version = ">= 0.13"
}

provider "vcd" {
  user     = var.vmwaas_user
  password = var.vmwaas_password
  #auth_type = "api_token"
  #api_token = var.vmwaas_api_token
  org       = var.vmwaas_org
  url       = var.vmwaas_url
  vdc       = var.vmwaas_vdc_name
}

