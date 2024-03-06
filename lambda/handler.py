import boto3
import json
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('pez-dynamodb')

class DecimalEncoder(json.JSONEncoder):
  def default(self, obj):
    if isinstance(obj, Decimal):
      return str(obj)
    return json.JSONEncoder.default(self, obj)
    
    
def handler(event, context):
    response = table.scan()
    return {
        'statusCode': 200,
        'body': json.dumps(response["Items"], cls=DecimalEncoder)
    }
