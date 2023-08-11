variable "aws_profile" {
  description = "The local AWS profile to use for terraform."
  type        = string
  default     = "[子账号1 Account ID]"
}

variable "bucket_name" {
  type        = string
  default     = "[bucket-name]"
}