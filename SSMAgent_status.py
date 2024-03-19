# lambda function to monitor PingStatus of SSM agents on managed ec2 instances with specific tags in regions you define, and report their PingStatus metric to a central Cloudwatch dashboard periodically. If Online, the metric is value 1, otherwise it's value is 0. The script also creates an alarm for the PingStatus metric and sends alert to an SNS topic you define when the Managed node is not Online. 
# Author : Charles Adebayo
# V2 : March 2024

import boto3
import botocore
import logging
import json

logger = logging.getLogger()
            
def lambda_handler(events,context):
    # define regions, cw_central_dashboard,tags, and cross_account_role_name where you want to monitor the managed nodes status and the tags for the specific managed nodes
    cw_central_dashboard = "eu-west-1"
    regions = ["eu-west-1", "us-east-2"]
    tags = {"auto-delete":"no"}
    cross_account_role_name = "AWS-SystemsManager-AutomationExecutionRole"
    sns_topic_arn = "arn:aws:sns:eu-west-1:<account_id>:SSMAgent_PingStatus_Topic"
    status = {} 
    # initialize the cloudwatch client
    cw = boto3.client('cloudwatch', region_name=cw_central_dashboard)
    # run the automaiton
    accounts = get_accounts(cross_account_role_name)
    get_ping_status(regions, tags, status, accounts)
    publish_cloudwatch_metric(status, cw)
    create_alarm(sns_topic_arn,status,cw)
    create_custom_dashboard(status,cw,cw_central_dashboard) 
    return status

def get_accounts(cross_account_role_name):
    iam_client = boto3.client('iam')
    sts_client = boto3.client('sts')
    org_client = boto3.client('organizations')

    account = sts_client.get_caller_identity().get('Account')
    try:    
        assumedRoleObject = sts_client.assume_role(
            RoleArn="arn:aws:iam::"+account+":role/"+cross_account_role_name,
            RoleSessionName="PingStatusAssumeRole-Lambda"
            )

        credentials = assumedRoleObject['Credentials']
        org_client = boto3.client(
            'organizations',
            aws_access_key_id = credentials['AccessKeyId'],
            aws_secret_access_key = credentials['SecretAccessKey'],
            aws_session_token = credentials['SessionToken'],
        )

        response = org_client.list_accounts()
        results = response["Accounts"]
        while "NextToken" in response:
            response = org_client.list_accounts(NextToken=response["NextToken"])
            results.extend(response["Accounts"])
        results = [result['Id'] for result in results]
        return results
    except botocore.exceptions.ClientError as error:
        raise error
    
def get_ping_status(regions, tags, status, accounts):
    tags_key = 'tag:'+list(tags.keys())[0]
    tags_value = list(tags.values())
    sts_client = boto3.client('sts')
    for account in accounts:
        assumedRoleObject = sts_client.assume_role(
            RoleArn="arn:aws:iam::"+account+":role/AWS-SystemsManager-AutomationExecutionRole",
            RoleSessionName="adebac-Lambda"
        )
        credentials = assumedRoleObject['Credentials']

        for region in regions:
            ssm = boto3.client('ssm', region_name=region, aws_access_key_id = credentials['AccessKeyId'],
                aws_secret_access_key = credentials['SecretAccessKey'],
                aws_session_token = credentials['SessionToken'],)   
            ec2 = boto3.client('ec2', region_name=region, aws_access_key_id = credentials['AccessKeyId'],
                aws_secret_access_key = credentials['SecretAccessKey'],
                aws_session_token = credentials['SessionToken'],)
            
            # get the list of currently running instances under the region using specific tags
            try: 
                ec2_response = ec2.describe_instances(
                    Filters=[
                        {
                            'Name': tags_key,
                                    'Values': tags_value,
                                },     
                    ],
                    MaxResults=50
                    )
                ec2_instances = ec2_response
                while "NextToken" in ec2_instances:
                    ec2_response = ec2.describe_instances(MaxResults=50,NextToken=response["NextToken"], Filters=[
                                {
                                    'Name': tags_key,
                                    'Values': tags_value,
                                },
                            ],)
                    ec2_instances.extend(ec2_response)
                ec2_instances_status = {instance['Instances'][0]["InstanceId"] : instance['Instances'][0]['State']['Name'] for instance in ec2_instances['Reservations']}
                ec2_instances = list(ec2_instances_status.keys())
            except botocore.exceptions.ClientError as error:
                raise error
            
            # print(f"for account {account} and region {region} printing list from describe instances API {ec2_instances}")
            
            # get the SSM agent ping status of all instances that are registered in Systems Manager filter using tags
            # create custom metric PingStatus for managed nodes
            # for managed instances that are not in Online state, set their PingStatus value to 1 (True), else set to 0 (False) 
            # for other ec2 instances not reporting to systems manager set their status as 'Missing' and PingStatus value to 1 (True)

            try:
                response = ssm.describe_instance_information(
                    Filters=[
                        {
                                'Key': tags_key,
                                'Values': tags_value,
                            },
                        ],
                    MaxResults=50
                )
                managed_nodes = response['InstanceInformationList']
                while "NextToken" in response:
                    response = ssm.describe_instance_information(MaxResults=50,NextToken=response["NextToken"],Filters=[
                            {
                                'Name': tags_key,
                                'Values': tags_value,
                            },
                        ],)
                    managed_nodes.extend(response['InstanceInformationList'])

                # add ec2 instances that are not terminated 
                # status.update({(instance['InstanceId'],account) : instance['PingStatus'] for instance in managed_nodes if instance['InstanceId'] in ec2_instances and ec2_instances_status[instance['InstanceId']] != "terminated"})
                
                # add hybrid nodes too
                # status.update({(instance['InstanceId'],account) : instance['PingStatus'] for instance in managed_nodes if instance['InstanceId'] not in ec2_instances})
                
                # print(f"for region {region} printing list from DII API  {managed_nodes}")
                for instance in managed_nodes:
                    if instance['InstanceId'] in ec2_instances:
                        if ec2_instances_status[instance['InstanceId']] != "terminated":
                            status.update({(instance['InstanceId'],account) : instance['PingStatus']})
                    else:
                        status.update({(instance['InstanceId'],account) : instance['PingStatus']})
                # if ec2 instance is not included in the describe_instance_information() response, and is not terminated add it as "Missing"
                status.update({(node,account): 'Missing' for node in ec2_instances if (node,account) not in status.keys() if ec2_instances_status[node] != "terminated"})
                
            except botocore.exceptions.ClientError as error:
                raise error
    print(f"final status list {status}")
    return

def publish_cloudwatch_metric(status,cw): 
    for instance in status:
        try:
            value = 0 if status[instance] == 'Online' else 1
            cw.put_metric_data(
                Namespace='PingStatus',
                MetricData=[{
                        'MetricName': 'PingStatus',
                        'Dimensions': [
                            {  'Name': 'InstanceId', 'Value': instance[0],},
                            ],
                        'Value': value,
                        'Unit': 'Count'
                                }]
                        )
            logger.info("Put data for metric PingStatus managed node",  instance)
        except botocore.exceptions.ClientError as error:
            logger.exception("Couldn't put data for PingStatusmanaged node", instance)
            raise error 
    return 

def create_alarm(sns_topic_arn,status,cw):
    for instance,account in status:
        AlarmName = 'SSMAgent_PingStatus-'+instance+"-"+account
        if not cw.describe_alarms(AlarmNames=[AlarmName])['MetricAlarms']:
            try:
                print("Creating Cloudwatch alarm for " + instance)
                cw.put_metric_alarm(
                AlarmName=AlarmName,
                ComparisonOperator='GreaterThanThreshold',
                EvaluationPeriods=1,
                DatapointsToAlarm=1,
                MetricName='PingStatus',
                Namespace='PingStatus',
                Period=300,
                Statistic='Average',
                Threshold=0,
                ActionsEnabled=True,
                AlarmActions=[
                    sns_topic_arn
                ],
                AlarmDescription='Alarm and send alert when PingStatus binary value switches to 1',
                Dimensions=[
                        {
                        'Name': 'InstanceId',
                        'Value': instance
                        }
                    ],
                TreatMissingData='missing'
                )
                
            except botocore.exceptions.ClientError as error:
                logger.exception("Couldn't create alarm for ", instance)
                raise error 
    return

def create_custom_dashboard(status, cw, cw_central_dashboard):
    # Initialize CloudWatch client
    # cloudwatch = boto3.client('cloudwatch', region_name=cw_central_dashboard)
    dashboard_name = "AWSOrganization-SSMAgentPingStatus"
    widgets_list = [{
                    "type": "text",
                    "x": 0,
                    "y": 0,
                    "width": 24,
                    "height": 6,
                    "properties": {
                        "markdown": "\n# AWSOrganization-SSMAgentPingStatus \n\n\nThis dashboard was generated by the SSMAgent-PingStatus-LambdaFunction Lambda Function to monitor PingStatus of SSM agents on managed ec2 instances with specific tags in regions you define, and report their PingStatus metric to a central Cloudwatch dashboard periodically. If Online, the metric is value 1, otherwise it's value is 0. The script also creates an alarm for the PingStatus metric and sends alert to an SNS topic you define when the Managed node is not Online. \n"
                    }
                }]
    # develop Dashboard widgets list for the managed nodes that are monitored
    for instance,account in status:
        title = f"{instance}_{account}_PingStatus"
        # Define the widget for the binary metric
        widgets_list.append({
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["PingStatus", "PingStatus", 'InstanceId',instance, { "color": "#d62728", "yAxis": "left" }]
                ],
                "view": "timeSeries",
                "region": cw_central_dashboard,
                "start": "-PT20M",
                "end": "P0D",
                "stat": "Maximum",
                "period": 300,
                "title": title,
            },
            "legend": {     
                "position": "bottom"
            },
            "yAxis": {
                "left": {
                   "label": "PingStatus Binary Value",
                   "showUnits": False
                         }
                    }
            })
    
    dashboard = {
        "widgets": widgets_list
        }
    
    # Create the custom dashboard if it doesn't exist before
    try:
        response = cw.put_dashboard(
                DashboardName=dashboard_name,
                DashboardBody=json.dumps(dashboard)
            )  
    except botocore.exceptions.ClientError as error:
        logger.exception("Couldn't create or update dashboard ", dashboard_name)
        raise error  
    return     
            
if __name__ == "__main__":
    lambda_handler(None,None)
