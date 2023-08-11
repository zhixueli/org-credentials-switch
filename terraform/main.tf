# 在 AWS provider 中指定目标账号的 profile
provider "aws" {
  region    = "us-east-1"
  profile   = var.aws_profile
}

data "aws_s3_objects" "all_objects" {
  bucket    = var.bucket_name
}

output "list_objects" {
    value = [for obj in data.aws_s3_objects.all_objects.keys : obj]
}