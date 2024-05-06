### resources to run on the GW

# define GW resources and config explained well at
# https://spacelift.io/blog/terraform-api-gateway#step-1-create-api-gateway
resource "aws_api_gateway_resource" "root" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  parent_id   = aws_api_gateway_rest_api.wf_api.root_resource_id
  path_part   = var.project_name
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
  rest_api_id   = aws_api_gateway_rest_api.wf_api.id
  resource_id   = aws_api_gateway_resource.root.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.wf_api.id
  resource_id             = aws_api_gateway_resource.root.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.wf_lambda_function.invoke_arn
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
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = aws_api_gateway_method_response.proxy.status_code

  //cors
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [
    aws_api_gateway_method.proxy,
    aws_api_gateway_integration.lambda_integration
  ]
}



#### CORS config

#  all the options stuff is for CORS
resource "aws_api_gateway_method" "options" {
  rest_api_id   = aws_api_gateway_rest_api.wf_api.id
  resource_id   = aws_api_gateway_resource.root.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id             = aws_api_gateway_rest_api.wf_api.id
  resource_id             = aws_api_gateway_resource.root.id
  http_method             = aws_api_gateway_method.options.http_method
  integration_http_method = "OPTIONS"
  type                    = "MOCK"
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

# i think this is needed for CORS but cbf
#resource "aws_api_gateway_deployment" "deployment" {
#  depends_on = [
#    aws_api_gateway_integration.lambda_integration,
#    aws_api_gateway_integration.options_integration, # Add this line
#  ]
#
#  rest_api_id = aws_api_gateway_rest_api.wf_api.id
#}



###  IAM to allow the API GW to invoke the Lambda function

# policy and permission #1 - give API GW permission to execute Lambda functions (#1-3)
# and then setting IAM policy in the Lambda function to allow this specific API GW to invoke it (#4)
# there are 4 components to this:
# 1. the role
# 2. the policy that the role grants
# 3. associates the policy with the role
# 4. permission applied to the lambda function that allows the API GW to invoke it

# component 1 - the role itself
resource "aws_iam_role" "lambda_role" {
  name               = "lambda-lambdaRole-apigw_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

# component 2 - the policy that allows the role to use Lambda
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

# component 3 - connects the policy and the role
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# componenet 4 - set IAM on the function to allow our specific API GW to invoke it
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wf_lambda_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.wf_api.execution_arn}/*/*/*"
}



### Lambda setup

# zip up the lambda function's code
data "archive_file" "python_lambda_package" {
  type        = "zip"
  source_file = "${path.module}/../app/lambda_function.py"
  output_path = "${path.module}/../app/${var.project_name}.zip"
}

# create the lambda function
resource "aws_lambda_function" "wf_lambda_function" {
  function_name    = var.project_name
  filename         = "${path.module}/../app/${var.project_name}.zip"
  source_code_hash = data.archive_file.python_lambda_package.output_base64sha256
  role             = aws_iam_role.lambda_role.arn
  runtime          = "python3.10"
  handler          = "lambda_function.lambda_handler"
  timeout          = 10
  depends_on       = [aws_cloudwatch_log_group.lambda_log_group]
}

# CW execution log retention for the lambda function
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.project_name}"
  retention_in_days = 1
  lifecycle {
    prevent_destroy = false
  }
}
