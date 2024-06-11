

module "container" {
  source = "terraform-google-modules/container-vm/google"
  version = "~> 2.0"

  container = {
    image="gcr.io/dataroc/pubsub-dlt-stream:${var.tag}"
    securityContext = {
      privileged : true
    }
    tty : true
    dynamic "env" {
      for_each = var.pubsub_dlt_stream_env
      content {
        name  = env.key
        value = env.value
      }
    }

    # Declare volumes to be mounted.
    # This is similar to how docker volumes are declared.
    volumeMounts = []
  }

  # Declare the Volumes which will be used for mounting.
  volumes = []

  restart_policy = "Always"
}

data "google_compute_image" "debian" {
  family  = "debian-11"
  project = "debian-cloud"
}

resource "google_compute_instance_template" "pubsub_dlt_stream" {
  name        = "instance-template"
  description = "This template is used to create pubsub-dlt-stream instances"

  // the `gce-container-declaration` key is very important
  metadata = {
    "gce-container-declaration" = module.container.metadata_value
  }
  labels = {
    "container-vm" = module.container.vm_container_label
  }

  machine_type         = var.machine_type
  can_ip_forward       = false

  scheduling {
    preemptible         = var.preemptible
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  // Create a new boot disk from an image
  disk {
    source_image      = data.google_compute_image.debian.self_link
    auto_delete       = true
    boot              = true
    disk_type         = "pd-balanced"
    disk_size_gb      = 10
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_group_manager" "pubsub_dlt_stream" {
  name               = "pubsub-dlt-stream"
  instance_template  = google_compute_instance_template.pubsub_dlt_stream.id
  base_instance_name = "pubsub-dlt-stream"
  zone               = var.google_region
  target_size        = var.target_size
}