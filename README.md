# Terraform module to stream Pub/Sub JSON to Cloud SQL on GCP

This module allows the deployment of the
[pubsub-dlt-stream](https://github.com/dataroche/pubsub-dlt-stream) worker code to an
auto-scaled instance group on GCP.

- Minimum throughput capacity of 700 messages/s per worker.
- Cost of $8.03/mth per active worker using n1-standard-1 spot machines.
- Auto-scaled using production-tested settings with configurable min/max replicas.

# Example usage

Given these variables as input:

```sh

# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# These variables are expected to be passed in by the operator
# ---------------------------------------------------------------------------------------------------------------------

variable "google_region" {
  description = "The region"
  type        = string
}

variable "target_database_name" {
  description = "The target database name"
  type        = string
}

variable "target_database_private_ip" {
  description = "The target database private ip"
  type        = string
}

variable "target_database_default_database_name" {
  description = "The target database default database name"
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# Generally, these values won't need to be changed.
# ---------------------------------------------------------------------------------------------------------------------


variable "sql_username" {
  description = "The SQL username"
  type        = string
  default     = "analytics_producer"
}

```

Our new backend uses the
[github.com/dataroche/terraform-gcp-pubsub-dlt-stream](https://github.com/dataroche/terraform-gcp-pubsub-dlt-stream)
module as follow. This should be adapted to your use-case, as it includes the service
account creation, Pub/Sub setup and Cloud SQL user (but not the creation of the database
instance itself)

```sh

data "google_project" "project" {}

locals {
  roles = [
    "roles/cloudsql.client",
    "roles/pubsub.subscriber",
    "roles/logging.logWriter"
  ]
}

# Create a new service account only for this.
resource "google_service_account" "service_account" {
  account_id   = "events-processor"
  display_name = "Events Processor"
}

resource "google_project_iam_member" "sa_binding" {
  project = data.google_project.project.project_id
  for_each = toset(local.roles)
  role    = each.key
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

# Generate a password for a new PostgreSQL user.
resource "random_password" "password" {
  length = 16
  special = true
}

# Create a PostgreSQL user
resource "google_sql_user" "iam_user" {
  instance = var.target_database_name
  name     = var.sql_username
  password = random_password.password.result
  type     = "BUILT_IN"
}

# Create the Pub/Sub topic that will be streamed to PostgreSQL
resource "google_pubsub_topic" "events" {
  name = "events-topic"
}

resource "google_pubsub_subscription" "events" {
  name  = "events-subscription"
  topic = google_pubsub_topic.events.id

  # 20 minutes
  message_retention_duration = "1200s"
  retain_acked_messages = true

  ack_deadline_seconds = 20

  expiration_policy {
    ttl = "300000.5s"
  }
  retry_policy {
    minimum_backoff = "10s"
  }

  enable_message_ordering = false
}

module "pubsub_dlt_stream" {
  source = "github.com/dataroche/terraform-gcp-pubsub-dlt-stream?ref=master"
  google_region = var.google_region
  service_account_email = google_service_account.service_account.email
  pubsub_dlt_stream_env = {
    "DESTINATION_NAME" = "postgres"
    "DESTINATION__POSTGRES__CREDENTIALS" = "postgresql://${var.sql_username}:${random_password.password.result}@${var.target_database_private_ip}:5432/${var.target_database_default_database_name}"
    "LOAD__DELETE_COMPLETED_JOBS" = "1"
    "DATASET_NAME" = "analytics"
    "WINDOW_SIZE_SECS" = "5"
    "MAX_BUNDLE_SIZE" = "5000"
    "PUBSUB_INPUT_SUBSCRIPTION" = google_pubsub_subscription.events.id
    "TABLE_NAME_DATA_KEY" = "eventName"
    "TABLE_NAME_PREFIX" = "raw_events_"
  }
  machine_type = "n1-standard-1"
  preemptible = true
  autoscale_min_replicas = 1
  autoscale_max_replicas = 5
}

```
