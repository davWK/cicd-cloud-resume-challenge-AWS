import json
import boto3
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('visitors')
def lambda_handler(event, context):
    response = table.get_item(Key={
            'id':'0'
    })
    count = response['Item']['count']
    count = count + 1

    response = table.put_item(Item={
            'id':'0',
            'count': count
    })

    return "one visitor added"
