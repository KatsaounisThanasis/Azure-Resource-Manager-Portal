# GCP Compute Engine Instance - Equivalent to Azure Virtual Machine
# This template creates a Compute Engine VM instance

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "instance_name" {
  type        = string
  description = "Name of the Compute Engine instance"
}

variable "machine_type" {
  type        = string
  description = "Machine type - affects cost and performance (e2-micro=free tier eligible, e2-medium=balanced, n1/n2-standard=production workloads)"
  default     = "e2-micro"
}

variable "zone" {
  type        = string
  description = "Zone to create the instance in (region + zone letter)"

  validation {
    condition = can(regex("^(us-central1|us-east1|us-west1|europe-west1|europe-west2|europe-west4|asia-east1|asia-southeast1)-(a|b|c|d|e|f)$", var.zone))
    error_message = "Zone must be a valid GCP zone (e.g., us-central1-a, europe-west1-b)"
  default = "us-central1-a"
}
}

variable "image_family" {
  type        = string
  description = "OS image family - affects operating system (debian-12, ubuntu-2204-lts, rocky-linux-9, windows-2022, etc.)"
  default     = "debian-12"
}

variable "image_project" {
  type        = string
  description = "Project containing the image"
  default     = "debian-cloud"
}

variable "disk_size_gb" {
  type        = number
  description = "Boot disk size in GB"
  default     = 20
}

variable "network" {
  type        = string
  description = "Network to attach to"
  default     = "default"
}

variable "subnet" {
  type        = string
  description = "Subnet to attach to"
  default     = "default"
}

variable "labels" {
  type        = map(string)
  description = "Labels to apply to the instance"
  default = {
    managed-by  = "terraform"
    environment = "production"
  }
}

# Get latest image
data "google_compute_image" "os_image" {
  family  = var.image_family
  project = var.image_project
}

# Firewall rule for HTTP/HTTPS
resource "google_compute_firewall" "http_https" {
  name    = "${var.instance_name}-allow-http-https"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.instance_name}-http"]
}

# Firewall rule for SSH
resource "google_compute_firewall" "ssh" {
  name    = "${var.instance_name}-allow-ssh"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.instance_name}-ssh"]
}

# Compute Engine Instance
resource "google_compute_instance" "main" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  tags = [
    "${var.instance_name}-http",
    "${var.instance_name}-ssh"
  ]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.os_image.self_link
      size  = var.disk_size_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnet

    # Assign external IP
    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  # Startup script (optional)
  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    systemctl start nginx
    systemctl enable nginx
    echo "<h1>Hello from GCP Compute Engine!</h1>" > /var/www/html/index.html
  EOT

  service_account {
    # Google recommends custom service accounts with minimal permissions
    # For now, using default with cloud-platform scope
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  labels = var.labels
}

# Static External IP (optional)
resource "google_compute_address" "static_ip" {
  name   = "${var.instance_name}-ip"
  region = regex("^([a-z]+-[a-z]+[0-9])", var.zone)[0]
}

# Outputs
output "instance_id" {
  description = "ID of the instance"
  value       = google_compute_instance.main.instance_id
}

output "instance_name" {
  description = "Name of the instance"
  value       = google_compute_instance.main.name
}

output "internal_ip" {
  description = "Internal IP address"
  value       = google_compute_instance.main.network_interface[0].network_ip
}

output "external_ip" {
  description = "External IP address"
  value       = google_compute_instance.main.network_interface[0].access_config[0].nat_ip
}

output "static_ip" {
  description = "Reserved static IP address"
  value       = google_compute_address.static_ip.address
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "gcloud compute ssh ${var.instance_name} --zone=${var.zone}"
}

output "web_url" {
  description = "Web URL to access the instance"
  value       = "http://${google_compute_instance.main.network_interface[0].access_config[0].nat_ip}"
}
