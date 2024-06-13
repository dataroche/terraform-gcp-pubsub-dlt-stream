data "google_project" "project" {}

module "container" {
  source = "terraform-google-modules/container-vm/google"
  version = "~> 3.0"

  # The latest COS image 113 seems to have disabled support for logging with the google-logging-enabled label
  cos_image_name="cos-stable-109-17800-66-43"

  container = {
    image="registry.hub.docker.com/dataroc/pubsub-dlt-stream:${var.tag}"=

    env = [
      for key, value in var.pubsub_dlt_stream_env : {
        name  = key
        value = value
      }
    ]

    # Declare volumes to be mounted.
    # This is similar to how docker volumes are declared.
    volumeMounts = []
  }

  # Declare the Volumes which will be used for mounting.
  volumes = []

  restart_policy = "Always"
}

resource "google_compute_instance_template" "pubsub_dlt_stream" {
  name_prefix = "pubsub-dlt-stream-"
  description = "This template is used to create pubsub-dlt-stream instances"

  // the `gce-container-declaration` key is very important
  metadata = {
    gce-container-declaration = module.container.metadata_value
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"
  }
  labels = {
    "container-vm" = module.container.vm_container_label
  }

  machine_type         = var.machine_type
  can_ip_forward       = false

  scheduling {
    preemptible         = var.preemptible
    automatic_restart   = !var.preemptible
    on_host_maintenance = var.preemptible ? "TERMINATE" : "MIGRATE"
  }

  // Create a new boot disk from an image
  disk {
    source_image      = module.container.source_image
    auto_delete       = true
    boot              = true
    disk_type         = "pd-balanced"
    disk_size_gb      = 10
  }
  
  network_interface {
    network = "default"
    access_config {} // Important: will assign an ephemeral external IP, which is required
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "google_compute_region_instance_group_manager" "pubsub_dlt_stream" {
  provider = google-beta
  project = data.google_project.project.project_id
  name               = "pubsub-dlt-stream-group-manager"
  version {
    instance_template = google_compute_instance_template.pubsub_dlt_stream.self_link_unique
  }
  base_instance_name = "pubsub-dlt-stream"
  region             = var.google_region
  target_size        = var.target_size

  update_policy {
    type                           = "PROACTIVE"
    instance_redistribution_type   = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed                = 10
    min_ready_sec                  = 50
    replacement_method             = "SUBSTITUTE"
  }
}

resource "google_compute_region_autoscaler" "pubsub_dlt_stream" {
  name   = "pubsub-dlt-stream-autoscaler"
  region = var.google_region
  target = google_compute_region_instance_group_manager.pubsub_dlt_stream.id

  autoscaling_policy {
    max_replicas    = var.autoscale_max_replicas
    min_replicas    = var.autoscale_min_replicas
    cooldown_period = 60

    cpu_utilization {
      target = 0.5
    }
  }
}