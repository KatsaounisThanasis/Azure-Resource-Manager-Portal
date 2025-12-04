# GCP Cloud Function - Equivalent to Azure Function App / AWS Lambda
# This template creates a Cloud Function (Gen 2) with HTTP trigger

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "function_name" {
  type        = string
  description = "Name of the Cloud Function"
}

variable "region" {
  type        = string
  description = "GCP region for resource deployment"
  default = "us-central1"
}

variable "runtime" {
  type        = string
  description = "Runtime environment - affects what language your function is written in (python311, nodejs20, go121, java17, etc.)"

  validation {
    condition = contains([
      "python311", "python310", "python39",
      "nodejs20", "nodejs18",
      "go121", "go119",
      "java17", "java11",
      "dotnet6", "dotnet3",
      "ruby32", "ruby30"
    ], var.runtime)
    error_message = "Invalid runtime specified"
  }
}

variable "entry_point" {
  type        = string
  description = "Function entry point"
  default     = "handler"
}

variable "memory_mb" {
  type        = number
  description = "Memory limit in MB - affects cost and performance"
  default     = 256

  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.memory_mb)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192"
  }
}

variable "timeout_seconds" {
  type        = number
  description = "Function timeout in seconds"
  default     = 60

  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 540
    error_message = "Timeout must be between 1 and 540 seconds"
  }
}

variable "environment_variables" {
  type        = map(string)
  description = "Environment variables"
  default     = {}
}

variable "labels" {
  type        = map(string)
  description = "Labels to apply to the function"
  default = {
    managed-by  = "terraform"
    environment = "production"
  }
}

# Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.function_name}-source-${random_id.bucket_suffix.hex}"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  labels = var.labels
}

# Random suffix for unique bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Create zip file with placeholder function code
data "archive_file" "function_code" {
  type        = "zip"
  output_path = "/tmp/${var.function_name}.zip"

  source {
    content = <<-EOT
      # Placeholder Cloud Function code
      # Replace this with your actual application code

      import functions_framework

      @functions_framework.http
      def handler(request):
          """
          HTTP Cloud Function handler

          Args:
              request (flask.Request): The request object

          Returns:
              The response text, or any set of values that can be turned into a
              Response object using make_response
          """
          return {
              'message': 'Hello from Cloud Function! Replace this with your code.',
              'status': 'success'
          }, 200
    EOT

    filename = "main.py"
  }

  source {
    content = <<-EOT
      functions-framework==3.*
    EOT

    filename = "requirements.txt"
  }
}

# Upload function source code to bucket
resource "google_storage_bucket_object" "function_code" {
  name   = "${var.function_name}-${data.archive_file.function_code.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_code.output_path
}

# Cloud Function (Gen 2)
resource "google_cloudfunctions2_function" "main" {
  name     = var.function_name
  location = var.region

  build_config {
    runtime     = var.runtime
    entry_point = var.entry_point

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_code.name
      }
    }
  }

  service_config {
    max_instance_count = 10
    min_instance_count = 0
    available_memory   = "${var.memory_mb}M"
    timeout_seconds    = var.timeout_seconds

    environment_variables = merge(
      {
        FUNCTION_NAME = var.function_name
        LOG_LEVEL     = "INFO"
      },
      var.environment_variables
    )

    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }

  labels = var.labels
}

# IAM binding to make function publicly accessible
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = google_cloudfunctions2_function.main.project
  location       = google_cloudfunctions2_function.main.location
  cloud_function = google_cloudfunctions2_function.main.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

# Outputs
output "function_name" {
  description = "Name of the function"
  value       = google_cloudfunctions2_function.main.name
}

output "function_url" {
  description = "HTTP URL of the function"
  value       = google_cloudfunctions2_function.main.service_config[0].uri
}

output "function_region" {
  description = "Region of the function"
  value       = google_cloudfunctions2_function.main.location
}

output "source_bucket" {
  description = "Source code bucket name"
  value       = google_storage_bucket.function_source.name
}

output "curl_command" {
  description = "cURL command to test the function"
  value       = "curl ${google_cloudfunctions2_function.main.service_config[0].uri}"
}
