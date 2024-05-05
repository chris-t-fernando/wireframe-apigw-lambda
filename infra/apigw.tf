variable "stage_name" {
  default = "dev"
  type    = string
}

resource "aws_cloudwatch_log_group" "wf_api_logs" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.wf_api.id}/${var.stage_name}"
  retention_in_days = 7
  # ... potentially other configuration ...
}

resource "aws_api_gateway_stage" "wf_api_stage_dev" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  deployment_id = aws_api_gateway_deployment.wf_api_deployment.id
  depends_on = [aws_cloudwatch_log_group.wf_api_logs]

  stage_name = var.stage_name
  # ... other configuration ...
}

resource "aws_api_gateway_rest_api" "wf_api" {
  name = "wf_api"
  description = "Wireframe API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "root" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  parent_id = aws_api_gateway_rest_api.wf_api.root_resource_id
  path_part = "wf_path_1"
}


resource "aws_api_gateway_deployment" "wf_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.wf_api.body))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.proxy,
    aws_api_gateway_integration.lambda_integration
  ]
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type = "AWS"
  uri = aws_lambda_function.test_lambda_function.invoke_arn
}

resource "aws_api_gateway_method_response" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = "200"

  //cors section
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = aws_api_gateway_method_response.proxy.status_code

  //cors
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" =  "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [
    aws_api_gateway_method.proxy,
    aws_api_gateway_integration.lambda_integration
  ]
}



// options
resource "aws_api_gateway_method" "options" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.options.http_method
  integration_http_method = "OPTIONS"
  type = "MOCK"
  #request_templates = {
  #  "application/json" = "{\"statusCode\": 200}"
  #}
}

resource "aws_api_gateway_method_response" "options_response" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = aws_api_gateway_method_response.options_response.status_code

  depends_on = [
    aws_api_gateway_method.options,
    aws_api_gateway_integration.options_integration
  ]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration.options_integration, # Add this line
  ]

  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  stage_name = "dev"
}







data "aws_iam_policy_document" "lambda_assume_role_policy" {
    statement {
        effect  = "Allow"
        actions = ["sts:AssumeRole"]
        principals {
            type        = "Service"
            identifiers = ["lambda.amazonaws.com"]
        }
    }
}

resource "aws_iam_role" "lambda_role" {
    name = "lambda-lambdaRole-apigw_role"
    assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "archive_file" "python_lambda_package" {  
  type = "zip"  
  source_file = "${path.module}/../app/lambda_function.py" 
  output_path = "wf_api.zip"
}

resource "aws_lambda_function" "test_lambda_function" {
  function_name = "wf_api"
  filename      = "wf_api.zip"
  source_code_hash = data.archive_file.python_lambda_package.output_base64sha256
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.10"
  handler       = "lambda_function.lambda_handler"
  timeout       = 10
}


resource "aws_api_gateway_account" "wf_api_cloudwatch" {
  cloudwatch_role_arn = aws_iam_role.cloudwatch.arn
}

resource "aws_iam_role" "cloudwatch" {
  name = "api_gateway_cloudwatch_global"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
            "lambda.amazonaws.com",
            "apigateway.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}