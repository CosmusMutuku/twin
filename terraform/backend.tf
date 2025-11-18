terraform {
  backend "s3" {
    bucket = ""  # will be set via -backend-config
    key    = ""  # will be set via -backend-config
    region = ""  # will be set via -backend-config
  }
}
