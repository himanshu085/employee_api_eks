terraform {
  backend "s3" {
    bucket         = "otms-terraform-state-891612580887"
    key            = "env/dev/otms/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "otms-tf-lock-891612580887"
    encrypt        = true
  }
}

