# Complete Monitoring and Alerting Setup

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "monitoring" {
  name                = "log-analytics-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Environment = var.environment
  }
}

# Diagnostic Settings for VMs
resource "azurerm_monitor_diagnostic_setting" "vm_diagnostics" {
  for_each = toset(var.vm_ids)

  name                       = "diag-setting-${each.key}"
  target_resource_id         = each.key
  log_analytics_workspace_id = azurerm_log_analytics_workspace.monitoring.id

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "Administrative"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }
}

# Action Group for Alerts
resource "azurerm_monitor_action_group" "alerts" {
  name                = "action-group-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "alert${var.environment}"

  dynamic "email_receiver" {
    for_each = var.alert_emails
    content {
      name                  = email_receiver.value.name
      email_address         = email_receiver.value.email
      use_common_alert_schema = true
    }
  }
}

# CPU Usage Alert
resource "azurerm_monitor_metric_alert" "cpu_high" {
  name                = "cpu-high-alert-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = var.vm_ids
  description         = "Alert when CPU usage exceeds 80% for 5 minutes"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
}

# VM Availability Alert
resource "azurerm_monitor_metric_alert" "vm_availability" {
  name                = "vm-availability-alert-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = var.vm_ids
  description         = "Alert when VM is unavailable"
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Availability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 99
  }
}

# RAM Usage Alert
resource "azurerm_monitor_metric_alert" "ram_usage" {
  name                = "ram-usage-alert-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = var.vm_ids
  description         = "Alert when RAM usage drops below threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Available Memory Bytes"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.memory_threshold
  }
}

# Disk Usage Alert
resource "azurerm_monitor_metric_alert" "disk_usage" {
  name                = "disk-usage-alert-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = var.vm_ids
  description         = "Alert when disk usage exceeds 90%"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "LogicalDisk % Free Space"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.disk_threshold
  }
}

# Variables
variable "environment" {
  description = "The environment (e.g., dev, qa, prod)"
  type        = string
}

variable "vm_ids" {
  description = "List of VM resource IDs to monitor"
  type        = list(string)
}

variable "alert_emails" {
  description = "List of email addresses for receiving alerts"
  type        = list(object({
    name  = string
    email = string
  }))
}

variable "memory_threshold" {
  description = "Threshold for available memory in bytes"
  type        = number
  default     = 536870912 # ~512MB
}

variable "disk_threshold" {
  description = "Threshold for free disk space in percentage"
  type        = number
  default     = 10
}

# Outputs
output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.monitoring.id
}

output "alert_group_ids" {
  value = azurerm_monitor_action_group.alerts.id
}
