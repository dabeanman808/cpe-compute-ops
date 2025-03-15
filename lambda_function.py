import os
import json
import logging
from datetime import datetime
from typing import Any, Dict

import boto3
from boto3.dynamodb.conditions import Key, Attr

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm_client = boto3.client("ssm")
ddb_client = boto3.resource("dynamodb")

TABLE_NAME = os.environ.get("DDB_TABLE", "resource_schedules")
RUNBOOK_NAME = os.environ.get("SSM_RUNBOOK_NAME", "StartStopInstancesRunbook")

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    This Lambda function runs on a schedule (via EventBridge) to check a DynamoDB table for resources
    needing to be started or stopped. It then uses SSM Automation to perform the start/stop.

    Environment Variables:
      - DDB_TABLE: The name of the DynamoDB table storing schedules.
      - SSM_RUNBOOK_NAME: The name of the SSM Automation Document to invoke (optional, default provided).
    """

    table = ddb_client.Table(TABLE_NAME)

    # Step 1: Scan or query the table for resources.
    try:
        response = table.scan()
        items = response.get("Items", [])
        logger.info(f"Found {len(items)} items in DynamoDB.")
    except Exception as e:
        logger.error(f"Error scanning DynamoDB table: {str(e)}")
        return {"statusCode": 500, "body": json.dumps("Error scanning DynamoDB.")}

    # For demonstration, we assume each item has:
    #  - ResourceID (unique string)
    #  - EC2InstanceId (the ID of the EC2 instance, e.g. i-0123456789abcdef0)
    #  - ShutdownTime, StartupTime (could be strings like '23:00', '08:00')
    #  - or anything else relevant for the schedule.

    now_utc = datetime.utcnow()
    current_hour = now_utc.hour

    # Step 2: Evaluate each resource.
    for item in items:
        resource_id = item.get("ResourceID")
        instance_id = item.get("EC2InstanceId")
        shutdown_time = item.get("ShutdownTime", "23")  # default to 23:00
        startup_time = item.get("StartupTime", "8")     # default to 08:00

        # Parse hours from the stored strings.
        try:
            shutdown_hour = int(shutdown_time.split(":")[0])
        except:
            shutdown_hour = 23
        try:
            startup_hour = int(startup_time.split(":")[0])
        except:
            startup_hour = 8

        # Decide if we should be 'running' or 'stopped' right now.
        # Example: if current_hour >= shutdown_hour or current_hour < startup_hour => STOP
        # Otherwise => START
        # Adjust logic to your actual schedule approach.
        if shutdown_hour > startup_hour:
            # e.g. startup at 8, shutdown at 23
            if current_hour >= shutdown_hour or current_hour < startup_hour:
                desired_action = "stop"
            else:
                desired_action = "start"
        else:
            # e.g. if shutdown at 1, startup at 15
            if shutdown_hour <= current_hour < startup_hour:
                desired_action = "stop"
            else:
                desired_action = "start"

        # Step 3: Call SSM Automation if instance_id is set.
        if instance_id:
            try:
                logger.info(f"Resource {resource_id} => {instance_id}: Invoking SSM runbook to {desired_action}.")
                ssm_client.start_automation_execution(
                    DocumentName=RUNBOOK_NAME,
                    Parameters={
                        "InstanceId": [instance_id],
                        "Action": [desired_action]
                    }
                )
            except Exception as ex:
                logger.error(f"Failed to start automation for {instance_id}: {str(ex)}")
        else:
            logger.warning(f"Item {resource_id} missing EC2InstanceId.")

    return {
        "statusCode": 200,
        "body": json.dumps("Schedule processing complete.")
    }

