# Input variable definitions

variable "aws_region" {
  description = "AWS region for all resources."

  type    = string
  default = "us-east-2"
}

variable "aws_access_key" {
  type        = string
  description = "AWS access key"
}
variable "aws_secret_key" {
  type        = string
  description = "AWS secret key"
}


variable "s3_bucket_prefix" {
  description = "S3 bucket prefix"
  type        = string
  default     = "crc-lambda"

}

variable "dynamodb_table" {
  description = "name of the ddb table"
  type        = string
  default     = "visitors"

}

variable "lambda_name" {
  description = "name of the lambda function"
  type        = string
  default     = "visitors_count"

}

variable "apigw_name" {
  description = "name of the lambda function"
  type        = string
  default     = "crc-http-lambda"

}

variable "lambda_log_retention" {
  description = "lambda log retention in days"
  type        = number
  default     = 7
}

variable "apigw_log_retention" {
  description = "api gwy log retention in days"
  type        = number
  default     = 7
}
