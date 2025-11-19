# ==============================================================================
# CRITICAL: Azure Provider Version
# ==============================================================================
# This module requires EXACTLY version 3.117.1 of the azurerm provider
# DO NOT change this version without testing thoroughly
# ==============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.117.1"  # EXACT version constraint - DO NOT MODIFY
    }
  }
  required_version = ">= 1.0"
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
