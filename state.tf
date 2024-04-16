
data "template_file" "step_function_definition" {
  template = file("${path.module}/step_function_definition.json")

  vars = {
    lambda_1_arn = aws_lambda_function.lambda_1.arn
    lambda_2_arn = aws_lambda_function.lambda_2.arn
  }
}

resource "aws_sfn_state_machine" "ecs_scale_down_sfn" {
  name     = "ecs-scale-down-sfn"
  role_arn = aws_iam_role.sfn_role.arn
  definition = data.template_file.step_function_definition.rendered
}