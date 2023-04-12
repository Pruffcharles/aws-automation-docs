# lambda function to monitor status of SSM agents on all managed nodes and ec2 instances in region and report their ConnectionLost metric to Cloudwatch.

import boto3
import botocore
import logging

logger = logging.getLogger()
            
def lambda_handler(events,context):
    
    # get the ssm client, and cloudwatch client, and ec2 resource here 
    ssm = boto3.client('ssm')
    cw = boto3.client('cloudwatch')
    ec2_resource = boto3.resource('ec2')
    status = {} 
    
    # get the list of currently running instances under the account
    ec2_instances = ec2_resource.instances.all()
    ec2_instances = [instance.id for instance in ec2_instances] 

    # get the SSM agent ping status of all instances that are registered in Systems Manager
    # create custom metric ConnectionLost for managed nodes
    # for managed instances that are not in Online state, set their ConnectionLost value to 1 (True), else set to 0 (False) 
    # for other ec2 instances not reporting to systems manager set their status as 'Missing' and ConnectionLost value to 1 (True)

    try:
        managed_nodes = ssm.describe_instance_information()
        managed_nodes = managed_nodes['InstanceInformationList']
        status = {instance['InstanceId'] : instance['PingStatus'] for instance in managed_nodes}
        
        status.update({node: 'Missing' for node in ec2_instances if node not in status.keys()})
        
        for i in status:
            try:
                value = 0 if status[i] == 'Online' else 1
                cw.put_metric_data(
                Namespace='EC2',
                MetricData=[{
                    'MetricName': 'ConnectionLost',
                    'Dimensions': [
                        {
                    'Name': 'InstanceId',
                    'Value': i,
                        },
                                ],
                    'Value': value,
                    'Unit': 'Count'
                            }]
                    )
                logger.info("Put data for metric ConnectionLost", 'EC2',  i)
            except botocore.exceptions.ClientError as error:
                logger.exception("Couldn't put data for ConnectionLost", 'EC2',  i)
                raise       
    except botocore.exceptions.ClientError as error:
        raise error
    
    return status
