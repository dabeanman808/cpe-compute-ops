terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.72.1"
    }
  }

  required_version = ">= 1.11.0"
}


provider "aws" {
  region = "us-west-1"
}
