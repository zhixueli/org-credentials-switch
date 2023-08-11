# 在 AWS 多账号环境中使用 Assume Role 的方式获取临时凭证方案
## 概览
* 原理：主账号上拥有最小可用权限的 Gateway user，通过调用子账号 assume role 接口，获取子账号拥有管理权限角色的临时身份凭证，对子账号进行管理操作
* Gateway user 通过 AKSK 发放，通过限制客户端 IP 地址限制其使用
* 方案可用于 AWS Organization，也可用于 AWS 上非 Organization 的多账号环境
* 临时凭证可以用于 AWS Cli，Python SDK（boto3），以及 Terraform
## 配置步骤概览
* 在子账号配置管理员角色，以及对主账号的信任关系
* 在主账号配置 Gateway user 以及最少需要的 IAM 权限
* 在本地客户端配置 AWS Cli credentials 文件
* 配置Python SDK（boto3）和 Terraform 客户端
## 具体配置步骤
### 在子账号配置管理员角色，以及对主账号的信任关系
1.  子账号创建具有管理权限的角色（role），假设取名为 AdminRole，并配置如下信任关系，允许主账号所有用户承担本角色获取临时身份，也可以限制为某些具体用户列表。
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::[主账号 Account ID]:root"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```
2. 角色创建完毕后，可以修改其 Maximum session duration（默认1小时，最长12小时），指定获取到的临时凭证的最长有效时长。最终具体时长需要在客户端请求临时凭证时配置。
### 在主账号配置 Gateway user 以及最少需要的 IAM 权限
1. 在主账号创建 Gateway user，假设取名为 gateway_user，创建如下 IAM Policy 并 attach 到 gateway_user。通过 IP 地址来限制客户端的使用。
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Resource": [
                "arn:aws:iam::[子账号1 Account ID]:role/AdminRole",
                "arn:aws:iam::[子账号2 Account ID]:role/AdminRole"
            ],
            "Condition": {
                "IpAddress": {
                    "aws:SourceIp": [
                        "52.94.133.0/24",
                        "72.21.198.0/24"
                    ]
                }
            }
        }
    ]
}
```
2. 为上述创建的 gateway_user 分配 AKSK
### 在本地客户端配置 AWS Cli credentials 文件
1. 本地打开AWS Cli credentials配置文件（$home/.aws/credentials），编辑文件加入如下 profiles 内容。 
```
[gateway_user]
aws_access_key_id = AKXXXXXXXXXXXX
aws_secret_access_key = SKXXXXXXXXXXXXXXXXXXXXXXXXX

[子账号1 Account ID]
role_arn = arn:aws:iam::[子账号1 Account ID]:role/AdminRole
source_profile = gateway_user
region = us-east-1
duration_seconds = 43200

[子账号2 Account ID]
role_arn = arn:aws:iam::[子账号2 Account ID]:role/AdminRole
source_profile = gateway_user
region = us-east-1
duration_seconds = 900
```
配置内容描述：
* Profile “gateway_user” 请填入上述步骤中新创建的 gateway_user 的 AKSK。
* Profile “子账号1 Account ID” 下：
    - role_arn 填入上述步骤中在子账号中创建的具有管理权限的角色名称；
    - source_profile 填入 gateway_user 的 profile 名称；
    - region 填入使用子账号的默认 region；
    - duration_seconds 填入临时凭证有效时长，最短15分钟，最长为上述步骤中子账号中创建的管理角色的 Maximum session duration 属性中的时长。客户端在使用临时凭证时，首先会检查本地已有临时凭证是否过期，过期之后会自动调用 assume role 接口重新申请，未过期则继续使用本地已有临时凭证。
* 为每一个需要管理的其他子账号仿照子账号1添加 profile。
2. AWS Cli 使用示例：
```
aws s3 ls --profile [子账号1 Account ID]
```
```
aws s3 ls --profile [子账号2 Account ID] --region eu-west-1
```
使用示例描述
* 使用 AWS Cli 命令时，--profile 参数请指定需要进行管理或操作的目标子账号的 profile，Cli 会使用这个子账号的 profile 中所设定的 source_profile（gateway_user） 的 AKSK 的身份自动调用子账号的 assume role 接口获取临时凭证
* AWS Cli 客户端在使用临时凭证时，首先会检查本地已有临时凭证是否过期，过期之后会自动调用 assume role 接口重新申请，未过期则继续使用本地已有临时凭证。过期时间通过子账号 profile 中的 duration_seconds 设置，默认为3600秒（1小时）。
### 配置Python SDK（boto3）和 Terraform 客户端
1. Python SDK（boto3）使用示例
```
import boto3
# 在 boto3 session 中指定目标账号的 profile
session = boto3.Session(profile_name='[子账号1 Account ID]')
dev_s3_client = session.client('s3')
response = dev_s3_client.list_buckets()
print(response)
```
2. Terraform 使用示例
main.tf
```
# 在 AWS provider 中指定目标账号的 profile
provider "aws" {
  region    = "us-east-1"
  profile   = var.aws_profile
}

data "aws_s3_objects" "all_objects" {
  bucket    = var.bucket_name
}

output "list_objects" {
    value = [for obj in data.aws_s3_objects.all_objects.keys : obj]
}
```
variable.tf
```
variable "aws_profile" {
  description = "The local AWS profile to use for terraform."
  type        = string
  default     = "[子账号1 Account ID]"
}

variable "bucket_name" {
  type        = string
  default     = "[bucket-name]"
}
```
