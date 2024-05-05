import boto3


def lambda_handler(event, context):
    result = "Hello World"
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": {"message": result},
    }
