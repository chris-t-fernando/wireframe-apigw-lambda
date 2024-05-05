# done once per region rather than per API GW or per resource which is weird but okay
# if its not done then CW logging won't work
# realistically this would live in a bootstrapping tf rather than in each API GW tf file


# get ARN for AWS managed policy that does this already
data "aws_iam_policy" "AmazonAPIGatewayPushToCloudWatchLogs" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "wf_api_cloudwatch" {
  cloudwatch_role_arn = aws_iam_role.cloudwatch.arn
}

# role to allows lambda and apigw to assume this role
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

# connects the policy with the permissions
resource "aws_iam_role_policy_attachment" "apigw_cloudwatch_attachment" {
  role       = aws_iam_role.cloudwatch.name
  policy_arn = data.aws_iam_policy.AmazonAPIGatewayPushToCloudWatchLogs.arn
}