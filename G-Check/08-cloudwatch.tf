############################################
# CloudWatch Logs (Log Group)
############################################

resource "aws_cloudwatch_log_group" "vandelay_log_group01" {
  name              = "/aws/ec2/${local.name_prefix}-rds-app"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-log-group01"
  }
}

############################################
# CloudWatch Alarm
############################################

resource "aws_cloudwatch_metric_alarm" "vandelay_db_alarm01" {
  alarm_name          = "${local.name_prefix}-db-connection-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DBConnectionErrors"
  namespace           = "Lab/RDSApp"
  period              = 300
  statistic           = "Sum"
  threshold           = 3

  alarm_actions = [aws_sns_topic.vandelay_sns_topic01.arn]
  ok_actions    = [aws_sns_topic.vandelay_sns_topic01.arn]

  tags = {
    Name = "${local.name_prefix}-alarm-db-fail"
  }
}

############################################
# SNS Topics
#
# Two topics to break the Lambda feedback loop:
#
#  vandelay-db-incidents  (TRIGGER topic)
#    - CloudWatch alarm publishes here
#    - incident-reporter Lambda subscribes here
#    - Nothing else subscribes → no loop
#
#  vandelay-notifications (NOTIFY topic)
#    - incident-reporter Lambda publishes here after report is done
#    - Email subscription lives here
#    - Lambda does NOT subscribe → no loop
############################################

resource "aws_sns_topic" "vandelay_sns_topic01" {
  name = "${local.name_prefix}-db-incidents"
}

# Separate outbound notification topic — Lambda publishes here,
# email subscription lives here. Lambda does NOT subscribe to this.
resource "aws_sns_topic" "vandelay_notifications" {
  name = "${local.name_prefix}-notifications"
}

# Email goes on the notification topic, not the trigger topic
resource "aws_sns_topic_subscription" "vandelay_sns_sub01" {
  topic_arn = aws_sns_topic.vandelay_notifications.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}