import boto3

# 在 boto3 session 中指定目标账号的 profile
session = boto3.Session(profile_name='[子账号1 Account ID]')
dev_s3_client = session.client('s3')
response = dev_s3_client.list_buckets()
print(response)