# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# These variables are expected to be passed in by the operator
# ---------------------------------------------------------------------------------------------------------------------

# Note, after a name db instance is used, it cannot be reused for up to one week.
variable "pubsub_dlt_stream_env" {
    description = <<EOT
    The execution environment for the pubsub-dlt-stream project - I.e.
    
    DESTINATION_NAME=postgres
    DESTINATION__POSTGRES__CREDENTIALS=postgresql://user:password@10.109.144.1:5432/db
    DATASET_NAME=analytics
    WINDOW_SIZE_SECS=5
    MAX_BUNDLE_SIZE=5000
    PUBSUB_INPUT_SUBSCRIPTION=projects/{PROJECT}/subscriptions/{SUBSCRIPTION_NAME}
    TABLE_NAME_DATA_KEY=eventName
    TABLE_NAME_PREFIX=raw_events_
    EOT
    type = map(string)
}

variable "service_account_email" {
    description = "The execution service account email address"
    type = string
}

variable "google_region" {
  description = "The region in which to run workers"
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# Generally, these values won't need to be changed.
# ---------------------------------------------------------------------------------------------------------------------

variable "tag" {
    description = "The docker tag to deploy"
    type = string
    default = "master"
}

variable "machine_type" {
    description = "The GCP machine type of the workers"
    type = string
    default = "e2-small"
}

variable "preemptible" {
    description = "If the workers are preemptible"
    type = bool
    default = false
}

variable "autoscale_min_replicas" {
  description = "The min instance group size"
  type        = number
  default     = 1
}

variable "autoscale_max_replicas" {
  description = "The max instance group size"
  type        = number
  default     = 5
}