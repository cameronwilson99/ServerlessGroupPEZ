provider "aws" {
  region = "us-east-2"
}

terraform {
  backend "s3" {
    bucket = "cw629-terraform-backend"
    key    = "ServerlessGroupPEZ/terraform.tfstate"
    region = "us-west-2"
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "main" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-2a"
}

resource "aws_subnet" "main2" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-2b"
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource aws_route_table "main" {
  vpc_id = aws_vpc.main.id

  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "main" {
  subnet_id = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "main" {
  vpc_id = aws_vpc.main.id
  name = "pez-sg"

  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_s3_bucket" "main" {
  bucket = "pez-bucket"
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id
  policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
          {
              Effect = "Allow",
              Principal = "*",
              Action = "s3:GetObject",
              Resource = "arn:aws:s3:::pez-bucket/*"
          }
      ]
  })
}

resource "aws_s3_object" "index" {
  bucket = aws_s3_bucket.main.id
  key    = "index.html"
  acl    = "public-read"
  content_type = "text/html"
  source = "${path.module}/../website/index.html"
  source_hash = md5(file("${path.module}/../website/index.html"))
}

resource "aws_s3_object" "app" {
  bucket = aws_s3_bucket.main.id
  key    = "app.js"
  acl    = "public-read"
  source = "${path.module}/../website/app.js"
  source_hash = md5(file("${path.module}/../website/app.js"))
}

resource "aws_cloudfront_distribution" "main" {
  origin {
      domain_name = aws_s3_bucket.main.bucket_regional_domain_name
      origin_id = "S3-${aws_s3_bucket.main.id}"
  }

  enabled = true
  is_ipv6_enabled = true
  default_root_object = "index.html"

  default_cache_behavior {
      allowed_methods = ["GET", "HEAD", "OPTIONS"]
      cached_methods = ["GET", "HEAD", "OPTIONS"]
      target_origin_id = "S3-${aws_s3_bucket.main.id}"
      viewer_protocol_policy = "allow-all"

      forwarded_values {
          query_string = false
          cookies {
              forward = "none"
          }
      }

      min_ttl     = 0
      default_ttl = 3600
      max_ttl     = 3600
  }

  restrictions {
      geo_restriction {
          restriction_type = "none"
      }
  }

  viewer_certificate {
      cloudfront_default_certificate = true
  }

  tags = {
      Name = "pez-cloudfront"
  }
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.main.domain_name
}

resource "aws_dynamodb_table" "main" {
  name = "pez-dynamodb"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "id"
  attribute {
      name = "id"
      type = "S"
  }
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "../lambda"
  output_path = "../build/packages/lambda.zip"
  output_file_mode = "0644"
}

resource "aws_s3_bucket" "backend" {
  bucket = "pez-backend"
}

resource "aws_s3_bucket_policy" "lambda_access" {
  bucket = aws_s3_bucket.backend.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action    = "s3:GetObject",
        Resource  = [
          "${aws_s3_bucket.backend.arn}/*",
        ],
      },
    ],
  })
}

resource "aws_s3_object" "lambda_upload" {
  bucket      = aws_s3_bucket.backend.id
  key         = "lambda/code.zip"
  source      = data.archive_file.lambda.output_path
  source_hash = data.archive_file.lambda.output_md5
}

resource "aws_lambda_function" "main" {
  function_name = "dynamodb-get-pez"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.11"
  timeout       = 30

  s3_bucket         = aws_s3_bucket.backend.id
  s3_key            = aws_s3_object.lambda_upload.key
  s3_object_version = aws_s3_object.lambda_upload.version_id

  depends_on = [ aws_s3_object.lambda_upload ]
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "pez-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_execution" {
  name = "lambda_execution_policy"
  role = aws_iam_role.iam_for_lambda.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "lambda:InvokeFunction",
          "dynamodb:Scan",
        ],
        Effect   = "Allow",
        Resource = [aws_lambda_function.main.arn],
      },
      {
        Action   = "dynamodb:Scan",
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn,
      },
    ],
  })
}

resource "aws_apigatewayv2_api" "main" {
  name          = "pez-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
  }
}

resource "aws_apigatewayv2_route" "main" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /pez"
  target    = "integrations/${aws_apigatewayv2_integration.main.id}"
}

resource "aws_apigatewayv2_integration" "main" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "AWS_PROXY"
  integration_uri    = "arn:aws:lambda:us-east-2:161506252702:function:dynamodb-get-pez"
  integration_method = "POST"
  payload_format_version = "2.0"
}

output "api_url" {
  value = aws_apigatewayv2_api.main.api_endpoint
}