### GW INSTANCE

# root API gateway resource
resource "aws_api_gateway_rest_api" "wf_api" {
  name        = "wf_api"
  description = "Wireframe API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# CloudWatch logging is set at the stage level, so explicitly instantiate one so we can attach method settings
# rest api > GW stage > GW method settings.cloudwatch config
resource "aws_api_gateway_stage" "wf_api_stage_dev" {
  rest_api_id   = aws_api_gateway_rest_api.wf_api.id
  deployment_id = aws_api_gateway_deployment.wf_api_deployment.id
  stage_name    = var.stage_name
  depends_on    = [aws_cloudwatch_log_group.wf_cw_logs]
}

# define gw method settings so we can set CW config
resource "aws_api_gateway_method_settings" "method_settings" {
  rest_api_id = aws_api_gateway_rest_api.wf_api.id
  stage_name  = aws_api_gateway_stage.wf_api_stage_dev.stage_name
  method_path = "*/*"
  settings {
    logging_level      = "INFO"
    data_trace_enabled = true
    metrics_enabled    = true
  }
}

resource "aws_cloudwatch_log_group" "wf_cw_logs" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.wf_api.id}/${var.stage_name}"
  retention_in_days = 1

}

