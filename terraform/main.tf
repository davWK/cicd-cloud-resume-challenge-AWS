terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.32.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4.3"
    }
    archive = {
      source  = "hashicorp/archive"
    }
  }

  required_version = ">= 1.2.0"

       backend "s3" {
       bucket = "alilikpo-infra-states"
       region = "eu-central-1"
     }


}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

resource "random_string" "random" {
  length  = 4
  special = false
}

#========================================================================
// Dynamodb setup
#========================================================================

resource "aws_dynamodb_table" "visitors" {
  name           = var.dynamodb_table
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

}

// Create DynamoDB Item #1
resource "aws_dynamodb_table_item" "item" {
  table_name = aws_dynamodb_table.visitors.name
  hash_key   = aws_dynamodb_table.visitors.hash_key
  item       = <<ITEM
 {
    "id": {"S": "0"},
    "count": {"N": "1"}
}
ITEM
}

#========================================================================
// lambda setup
#========================================================================

resource "aws_s3_bucket" "lambda_bucket" {
  bucket_prefix = var.s3_bucket_prefix
  force_destroy = true
}

resource "aws_s3_bucket_acl" "private_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id
  acl    = "private"
}

data "archive_file" "lambda_zip" {
  type = "zip"

  source_dir  = "${path.module}/src"
  output_path = "${path.module}/src.zip"
}

resource "aws_s3_object" "this" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "src.zip"
  source = data.archive_file.lambda_zip.output_path

  etag = filemd5(data.archive_file.lambda_zip.output_path)
}

//Define lambda function
resource "aws_lambda_function" "visitors_count" {
  function_name = "${var.lambda_name}-${random_string.random.id}"
  description   = "visitors count"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.this.key

  runtime = "python3.9"
  handler = "app.lambda_handler"

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  role = aws_iam_role.lambda_exec.arn


  depends_on = [aws_cloudwatch_log_group.lambda_logs]

}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name = "/aws/lambda/${var.lambda_name}-${random_string.random.id}"

  retention_in_days = var.lambda_log_retention
}

resource "aws_iam_role" "lambda_exec" {
  name = "LambdaDdbPost"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_exec_role" {
  name = "lambda-tf-pattern-ddb-post"

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem"
            ],
            "Resource": "arn:aws:dynamodb:*:*:table/${var.dynamodb_table}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec_role.arn
}

#========================================================================
// API Gateway section
#========================================================================

resource "aws_apigatewayv2_api" "http_lambda" {
  name          = "${var.apigw_name}-${random_string.random.id}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.http_lambda.id

  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
  depends_on = [aws_cloudwatch_log_group.api_gw]
}

resource "aws_apigatewayv2_integration" "apigw_lambda" {
  api_id = aws_apigatewayv2_api.http_lambda.id

  integration_uri    = aws_lambda_function.visitors_count.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "post" {
  api_id = aws_apigatewayv2_api.http_lambda.id

  route_key = "POST /visitors"
  target    = "integrations/${aws_apigatewayv2_integration.apigw_lambda.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${var.apigw_name}-${random_string.random.id}"

  retention_in_days = var.apigw_log_retention
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitors_count.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.http_lambda.execution_arn}/*/*"
}
