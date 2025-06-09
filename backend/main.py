from fastapi import FastAPI, HTTPException, status, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi import Request
import os
import json
import logging
import re
import urllib.parse
from datetime import datetime
from typing import Dict, Any, Optional
from azure.identity import DefaultAzureCredential, CredentialUnavailableError
from azure.mgmt.resource import ResourceManagementClient, SubscriptionClient
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.web import WebSiteManagementClient
from azure.core.exceptions import ResourceExistsError, ClientAuthenticationError
from fastapi.exception_handlers import RequestValidationError
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
from pydantic import BaseModel, Field

# Additional imports needed
import subprocess
import shutil

# Define a model for the parameter value structure
class ParameterValue(BaseModel):
    value: Any

# Utility functions (inline instead of importing from utils)
def get_azure_cli_path():
    az_path = shutil.which('az')
    if not az_path:
        az_path = r"C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
        if not os.path.exists(az_path):
            az_path = r"C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
            if not os.path.exists(az_path):
                logging.error("Azure CLI not found. Please ensure it is installed and in your PATH.")
                raise Exception("Azure CLI not found. Please ensure it is installed and in your PATH.")
    return az_path

def run_azure_cli_command(command, subscription_id: str | None = None):
    try:
        full_command = []
        az_path = get_azure_cli_path()

        # Always start with the az executable path
        full_command.append(az_path)

        if command[0] == 'bicep':
            # For bicep commands, add 'bicep' as the second argument
            full_command.append('bicep')
            # Add the rest of the command arguments as they are
            full_command.extend(command[1:])
        else:
            # For other az commands, add the rest of the command arguments
            if subscription_id:
                full_command.extend(["--subscription", subscription_id])
            full_command.extend(command)

        logging.info(f"Running Azure CLI command: {' '.join(full_command)}")
        result = subprocess.run(full_command, capture_output=True, text=True, shell=False)

        if result.stdout:
            logging.info(f"Azure CLI command stdout: {result.stdout.strip()}")
        if result.stderr:
            logging.error(f"Azure CLI command stderr: {result.stderr.strip()}")

        if result.returncode == 0 and result.stdout.strip():
            stdout_str = result.stdout.strip()
            json_start = -1
            json_end = -1
            array_start = stdout_str.find('[')
            object_start = stdout_str.find('{')
            if array_start != -1 and (object_start == -1 or array_start < object_start):
                json_start = array_start
                json_end = stdout_str.rfind(']')
            elif object_start != -1:
                json_start = object_start
                json_end = stdout_str.rfind('}')
            if json_start != -1 and json_end != -1 and json_end > json_start:
                json_string = stdout_str[json_start : json_end + 1]
                try:
                    return json.loads(json_string), result.returncode
                except json.JSONDecodeError:
                    logging.error(f"Failed to parse extracted JSON string: {json_string}")
                    return stdout_str, result.returncode
            else:
                logging.warning("No JSON structure found in Azure CLI stdout. Returning raw output and return code.")
                return stdout_str, result.returncode
        else:
            return result.stderr.strip(), result.returncode
    except subprocess.SubprocessError as e:
        logging.error(f"Error executing Azure CLI command: {e}")
        return f"Error executing Azure CLI command: {str(e)}", 1
    except Exception as e:
        logging.error(f"An unexpected error occurred while running Azure CLI command: {e}")
        return f"An unexpected error occurred: {str(e)}", 1

# Configure logging
os.makedirs("logs", exist_ok=True)  # Ensure logs directory exists
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/backend.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

def parse_bicep_parameters(content: str, include_metadata: bool = False):
    """
    Parse parameters from Bicep template content.
    Returns a list of parameter definitions or dict if include_metadata is True.
    """
    if include_metadata:
        params = {}
        param_pattern = re.compile(r'^\s*(@secure\(\)\s*)?(@description\(\s*[\'"]([^\'"]*)[\'"]?\s*\)\s*)?(param\s+)(\w+)\s+(\w+)(?:\s*=\s*(.*))?$', re.MULTILINE)
    else:
        params = []
        param_pattern = re.compile(r'^\s*(@secure\(\)\s*)?(param\s+)(\w+)\s+(\w+)(?:\s*=\s*(.*))?$', re.MULTILINE)
    
    for match in param_pattern.finditer(content):
        if include_metadata:
            is_secure = match.group(1) is not None
            description = match.group(3) if match.group(3) else ""
            param_name = match.group(5)
            param_type = match.group(6)
            default_value_content = match.group(7)
        else:
            is_secure = match.group(1) is not None
            param_name = match.group(3)
            param_type = match.group(4)
            default_value_content = match.group(5)
        
        default_value = None
        
        if default_value_content is not None:
            stripped_value = default_value_content.strip()
            if stripped_value:
                try:
                    default_value = json.loads(stripped_value)
                    if isinstance(default_value, str):
                        default_value = default_value.strip("'\"")
                except json.JSONDecodeError:
                    default_value = stripped_value.strip("'\"")
                except Exception as e:
                    logger.warning(f"Error parsing default value '{stripped_value}': {str(e)}")
                    default_value = stripped_value
        
        if is_secure and param_type.lower() == 'string':
            param_type = 'securestring'
        
        if param_name not in ["location", "resourceGroup"]:
            if include_metadata:
                params[param_name] = {
                    "type": param_type,
                    "defaultValue": default_value,
                    "metadata": {
                        "description": description
                    }
                }
            else:
                params.append({
                    "name": param_name,
                    "type": param_type,
                    "default": default_value
                })
    
    return params

app = FastAPI()

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Azure credentials
try:
    credential = DefaultAzureCredential()
except CredentialUnavailableError as e:
    print(f"Error initializing Azure credentials: {str(e)}")
    credential = None

# Absolute paths for static and template directories
FRONTEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend"))
TEMPLATES_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend"))

# Mount static files and templates using absolute paths
app.mount("/static", StaticFiles(directory=FRONTEND_DIR), name="static")

# Mount CSS and JS directories directly for cleaner URLs
CSS_DIR = os.path.join(FRONTEND_DIR, "css")
JS_DIR = os.path.join(FRONTEND_DIR, "js")

if os.path.exists(CSS_DIR):
    app.mount("/css", StaticFiles(directory=CSS_DIR), name="css")
if os.path.exists(JS_DIR):
    app.mount("/js", StaticFiles(directory=JS_DIR), name="js")

templates = Jinja2Templates(directory=TEMPLATES_DIR)

# Log startup info
logger.info(f"Backend started. Static dir: {FRONTEND_DIR}, Templates dir: {TEMPLATES_DIR}")
logger.info(f"CSS directory: {CSS_DIR if os.path.exists(CSS_DIR) else 'Not found'}")
logger.info(f"JS directory: {JS_DIR if os.path.exists(JS_DIR) else 'Not found'}")

@app.get("/")
async def read_root(request: Request):
    try:
        return templates.TemplateResponse("index.html", {"request": request})
    except Exception as e:
        logger.error(f"Error rendering index.html: {str(e)}")
        return JSONResponse(status_code=500, content={"message": "Failed to render index.html", "detail": str(e)})

# Routes
@app.get("/templates")
async def get_templates():
    logger.info("/templates endpoint called")
    templates_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "templates")
    templates = []
    if not os.path.exists(templates_dir):
        logger.error(f"Templates directory not found at {templates_dir}")
        return []
    for filename in os.listdir(templates_dir):
        if filename.endswith(".bicep"):
            template_name = filename.replace(".bicep", "")
            template_path = os.path.join(templates_dir, filename)
            try:
                with open(template_path, "r") as f:
                    content = f.read()
                params = parse_bicep_parameters(content)
                icon_name = "file-earmark"
                template_name_lower = template_name.lower()
                if template_name_lower == "aks":
                    icon_name = "boxes"
                elif template_name_lower == "cosmos db":
                    icon_name = "server"
                elif template_name_lower == "diagnostic settings":
                    icon_name = "gear"
                elif template_name_lower == "function app":
                    icon_name = "code-slash"
                elif template_name_lower == "keyvault":
                    icon_name = "lock"
                elif template_name_lower == "load balancer":
                    icon_name = "share"
                elif template_name_lower == "log analytics":
                    icon_name = "graph-up-arrow"
                elif template_name_lower == "nsg":
                    icon_name = "shield-check"
                elif template_name_lower == "public ip":
                    icon_name = "diagram-3"
                elif template_name_lower == "sql":
                    icon_name = "server"
                elif template_name_lower == "storage account":
                    icon_name = "hdd-stack"
                elif template_name_lower == "virtual machine ss":
                    icon_name = "pc-display"
                elif template_name_lower == "virtual machine":
                    icon_name = "pc-display"
                elif template_name_lower == "virtual network":
                    icon_name = "diagram-3"
                elif template_name_lower == "web app":
                    icon_name = "globe"
                templates.append({
                    "template": template_name,
                    "params": params,
                    "icon": icon_name
                })
                logger.info(f"Backend sending icon '{icon_name}' for template '{template_name}'.")
            except FileNotFoundError:
                logger.warning(f"Template file not found: {template_path}")
                continue
            except Exception as e:
                logger.error(f"Error processing template file {filename}: {str(e)}")
                continue
    logger.info(f"/templates endpoint returning {len(templates)} templates")
    return templates

@app.get("/templates/{template_name}/parameters")
async def get_template_parameters(template_name: str):
    """
    Get parameters for a specific template.
    Returns the parameter definitions for the specified Bicep template.
    """
    logger.info(f"/templates/{template_name}/parameters endpoint called")
    
    # Decode URL-encoded template name
    template_name = urllib.parse.unquote(template_name)
    logger.info(f"Decoded template name: {template_name}")
    
    templates_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "templates")
    template_path = os.path.join(templates_dir, f"{template_name}.bicep")
    
    if not os.path.exists(template_path):
        logger.error(f"Template file not found: {template_path}")
        raise HTTPException(status_code=404, detail=f"Template '{template_name}' not found")
    
    try:
        with open(template_path, "r") as f:
            content = f.read()
        
        # Parse parameters from the Bicep template
        params = parse_bicep_parameters(content, include_metadata=True)
        
        logger.info(f"Returning {len(params)} parameters for template '{template_name}'")
        return params
        
    except Exception as e:
        logger.error(f"Error processing template file {template_path}: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error processing template: {str(e)}")

class DeploymentRequest(BaseModel):
    template_name: str = Field(..., min_length=1, max_length=100)
    parameters: Dict[str, Any]
    subscription_id: str = Field(..., min_length=1, max_length=100)
    resource_group: str = Field(..., min_length=1, max_length=90, pattern=r'^[-\w\._\(\)]+$')
    location: str = Field(..., min_length=1, max_length=100)

@app.post("/deploy")
async def deploy_template(request: DeploymentRequest):
    try:
        # Initialize Azure clients
        resource_client = ResourceManagementClient(credential, request.subscription_id)
        
        # Create resource group if it doesn't exist
        try:
            resource_client.resource_groups.create_or_update(
                request.resource_group,
                {"location": request.location}
            )
        except ResourceExistsError:
            pass
        except Exception as e:
            logger.error(f"Error creating/updating resource group: {str(e)}")
            raise HTTPException(status_code=500, detail=f"Error creating/updating resource group: {str(e)}")

        # Get template content
        template_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "templates", f"{request.template_name}.bicep")
        if not os.path.exists(template_path):
            raise HTTPException(status_code=404, detail=f"Template {request.template_name} not found")
            
        try:
            with open(template_path, "r") as f:
                template_content = f.read()
        except Exception as e:
            logger.error(f"Error reading template file: {str(e)}")
            raise HTTPException(status_code=500, detail=f"Error reading template file: {str(e)}")

        # Compile Bicep template to ARM JSON
        try:
            # Use the actual template_path for the build command
            build_command = ['bicep', 'build', '--file', template_path]
            arm_template_json_str, returncode = run_azure_cli_command(build_command)
            
            if returncode != 0:
                logger.error(f"Bicep build failed for {request.template_name}.bicep. Return code: {returncode}")
                raise HTTPException(status_code=500, detail=f"Failed to compile Bicep template: {request.template_name}.bicep")
            
            # Check if the output is just a warning message
            if "WARNING:" in arm_template_json_str:
                # If it's just a warning, try to read the compiled JSON file directly
                json_path = template_path.replace('.bicep', '.json')
                try:
                    with open(json_path, 'r') as f:
                        arm_template_json = json.load(f)
                except Exception as e:
                    logger.error(f"Failed to read compiled JSON file: {str(e)}")
                    raise HTTPException(status_code=500, detail=f"Failed to read compiled Bicep template: {str(e)}")
            else:
                # Parse the JSON output
                try:
                    arm_template_json = json.loads(arm_template_json_str)
                except json.JSONDecodeError as e:
                    logger.error(f"Failed to parse Bicep build output as JSON: {str(e)}. Output: {arm_template_json_str[:500]}...")
                    raise HTTPException(status_code=500, detail=f"Failed to parse Bicep build output: {str(e)}")
            
            logger.info(f"Successfully compiled {request.template_name}.bicep to ARM JSON.")

        except FileNotFoundError:
            logger.error("Azure CLI not found. Please ensure it is installed and in your PATH.")
            raise HTTPException(status_code=500, detail="Azure CLI not found. Please ensure it is installed and in your PATH.")
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse Bicep build output as JSON: {str(e)}. Output: {arm_template_json_str[:500]}...")
            raise HTTPException(status_code=500, detail=f"Failed to parse Bicep build output: {str(e)}")
        except Exception as e:
            logger.error(f"Error during Bicep compilation: {str(e)}")
            raise HTTPException(status_code=500, detail=f"Error during Bicep compilation: {str(e)}")

        # Deploy template
        deployment_name = f"deployment-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
          # Transform parameters to the format expected by Azure API
        azure_parameters = {}
        
        # Always include location parameter from the request
        azure_parameters["location"] = {"value": request.location}
        
        # Get template parameter definitions to understand expected types
        template_params = arm_template_json.get("parameters", {})
        
        for param_name, param_value in request.parameters.items():
            # Handle cases where the value might be None (e.g., optional parameters not provided)
            if param_value is not None:
                # "Flatten" nested {"value": ...} structures
                actual_value = param_value
                while isinstance(actual_value, dict) and "value" in actual_value:
                    actual_value = actual_value["value"]

                # Get the expected parameter type from the template
                param_def = template_params.get(param_name, {})
                expected_type = param_def.get("type", "").lower()                # Transform value based on expected type
                try:
                    if expected_type == "array":
                        if isinstance(actual_value, str):
                            # Try to parse as JSON array first
                            try:
                                actual_value = json.loads(actual_value)
                                if not isinstance(actual_value, list):
                                    actual_value = [actual_value]  # Wrap single value in array
                            except json.JSONDecodeError:
                                # If not JSON, split by comma or treat as single item array
                                actual_value = [item.strip() for item in actual_value.split(",")] if "," in actual_value else [actual_value]
                        elif not isinstance(actual_value, list):
                            actual_value = [actual_value]  # Wrap single value in array
                    elif expected_type == "object":
                        if isinstance(actual_value, str):
                            try:
                                actual_value = json.loads(actual_value)
                            except json.JSONDecodeError:
                                # If not valid JSON, create empty object
                                actual_value = {}
                    elif expected_type == "bool":
                        if isinstance(actual_value, str):
                            actual_value = actual_value.lower() in ("true", "yes", "1", "on")
                        else:
                            actual_value = bool(actual_value)
                    elif expected_type == "int":
                        actual_value = int(actual_value) if actual_value != "" else 0
                    # For string types, keep as is
                except (ValueError, TypeError) as e:
                    logger.warning(f"Failed to convert parameter '{param_name}' to expected type '{expected_type}': {str(e)}. Using original value.")
                
                # Wrap the actual value in the {"value": ...} format required by Azure
                azure_parameters[param_name] = { "value": actual_value }

        deployment_properties = {
            "template": arm_template_json,
            "parameters": azure_parameters,
            "mode": "Incremental"
        }

        try:
            deployment = resource_client.deployments.begin_create_or_update(
                request.resource_group,
                deployment_name,
                {"properties": deployment_properties}
            ).result()
            
            logger.info(f"Deployment {deployment_name} completed successfully. ID: {deployment.id}")
            
        except Exception as e:
            logger.error(f"Error during deployment: {str(e)}")
            
            # Extract more detailed error information if available
            error_details = str(e)
            if hasattr(e, 'error') and hasattr(e.error, 'message'):
                error_details = e.error.message
            elif hasattr(e, 'message'):
                error_details = e.message
                
            logger.error(f"Detailed deployment error: {error_details}")
            raise HTTPException(status_code=500, detail=f"Deployment failed: {error_details}")
              # Log deployment success
        deployment_log = {
            "timestamp": datetime.now().isoformat(),
            "template": request.template_name,
            "parameters": request.parameters,
            "status": "success",
            "deployment_id": deployment.id,
            "deployment_name": deployment_name,
            "resource_group": request.resource_group
        }
        
        try:
            os.makedirs("logs", exist_ok=True)
            with open("logs/deployments.log", "a") as f:
                f.write(json.dumps(deployment_log) + "\n")
            logger.info(f"Deployment logged successfully: {deployment_name}")
        except Exception as e:
            logger.error(f"Error writing to deployment log: {str(e)}")
            # Don't raise an exception here as the deployment was successful

        return {
            "status": "success", 
            "deployment_id": deployment.id,
            "deployment_name": deployment_name,
            "message": f"Template '{request.template_name}' deployed successfully to resource group '{request.resource_group}'"
        }

    except HTTPException:
        # Re-raise HTTP exceptions (these are expected errors)
        raise
    except Exception as e:
        logger.error(f"Deployment failed: {str(e)}")
        
        # Log the failure
        failure_log = {
            "timestamp": datetime.now().isoformat(),
            "template": request.template_name,
            "parameters": request.parameters,
            "status": "failed",
            "error": str(e),
            "resource_group": request.resource_group
        }
        
        try:
            os.makedirs("logs", exist_ok=True)
            with open("logs/deployments.log", "a") as f:
                f.write(json.dumps(failure_log) + "\n")
        except Exception as log_e:
            logger.error(f"Failed to log deployment failure: {str(log_e)}")
            
        raise HTTPException(status_code=500, detail=f"Deployment failed: {str(e)}")

@app.get("/deployments")
async def list_deployments(subscription_id: str | None = None):
    deployments = []
    log_file = "logs/deployments.log"
    
    if not os.path.exists(log_file):
        return deployments
        
    try:
        with open(log_file, "r") as f:
            for line in f:
                line = line.strip()
                if not line or not (line.startswith("{") and line.endswith("}")):
                    continue
                try:
                    obj = json.loads(line)
                    # Check if this looks like a deployment record (has required minimum fields)
                    required_fields = ("timestamp", "template", "status")
                    if isinstance(obj, dict) and all(k in obj for k in required_fields):
                        # Ensure we have deployment_id (some old records might not have it)
                        if "deployment_id" not in obj:
                            obj["deployment_id"] = f"legacy-{obj.get('timestamp', 'unknown')}"
                        # Ensure we have parameters (some records might not have it)
                        if "parameters" not in obj:
                            obj["parameters"] = {}
                        deployments.append(obj)
                except json.JSONDecodeError as parse_exc:
                    logger.debug(f"Skipping invalid JSON line in deployments.log: {line[:100]}... ({parse_exc})")
                except Exception as e:
                    logger.error(f"Error processing deployment log line: {str(e)}")
                    continue
    except FileNotFoundError:
        logger.warning("Deployments log file not found")
    except PermissionError:
        logger.error("Permission denied when accessing deployments log file")
        raise HTTPException(status_code=500, detail="Permission denied when accessing deployments log")
    except Exception as e:
        logger.error(f"Error reading deployments log: {str(e)}")
        raise HTTPException(status_code=500, detail="Error reading deployments log")
    
    # Sort deployments by timestamp (newest first)
    try:
        deployments.sort(key=lambda x: x.get('timestamp', ''), reverse=True)
    except Exception as e:
        logger.warning(f"Error sorting deployments: {str(e)}")
        
    return deployments

@app.get("/subscriptions")
async def list_subscriptions():
    logger.info("/subscriptions endpoint called")
    try:
        # Use SubscriptionClient to list all accessible subscriptions
        subscription_client = SubscriptionClient(credential)
        subscriptions_list = list(subscription_client.subscriptions.list())
        logger.info(f"/subscriptions endpoint returning {len(subscriptions_list)} subscriptions")
        return [{"id": sub.subscription_id, "name": sub.display_name} for sub in subscriptions_list]
    except Exception as e:
        logger.error(f"Failed to get subscriptions: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

class ResourceGroupCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=90, pattern=r'^[-\w\._\(\)]+$')
    location: str = Field(..., min_length=1)
    subscription_id: str = Field(..., min_length=1)

@app.post("/resource-groups")
async def create_resource_group(request: ResourceGroupCreateRequest):
    try:
        if not credential:
            raise HTTPException(status_code=500, detail="Azure credentials not initialized.")
            
        resource_client = ResourceManagementClient(credential, request.subscription_id)
        
        resource_group = resource_client.resource_groups.create_or_update(
            request.name,
            {"location": request.location}
        )
        
        logger.info(f"Resource group {request.name} created/updated successfully in subscription {request.subscription_id}.")
        return {"status": "success", "name": resource_group.name, "location": resource_group.location}
        
    except ResourceExistsError:
        logger.warning(f"Attempted to create resource group {request.name} that already exists.")
        raise HTTPException(status_code=409, detail=f"Resource group {request.name} already exists.")
    except Exception as e:
        logger.error(f"Failed to create resource group {request.name}: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to create resource group: {str(e)}")

@app.get("/resource-groups")
async def list_resource_groups(subscription_id: str | None = None):
    try:
        current_subscription_id = subscription_id
        if not current_subscription_id:
            try:
                account_info_output, account_returncode = run_azure_cli_command(['account', 'show'])
                if account_returncode == 0 and isinstance(account_info_output, dict) and account_info_output.get("id"):
                    current_subscription_id = account_info_output["id"]
                    logger.info(f"Using default subscription from Azure CLI: {current_subscription_id}")
                else:
                    raise HTTPException(status_code=400, detail="Subscription ID is required or login to Azure CLI with a default subscription.")
            except Exception as cli_e:
                logger.error(f"Error getting default subscription from Azure CLI: {cli_e}")
                raise HTTPException(status_code=500, detail=f"Could not determine default subscription: {str(cli_e)}")

        if not credential:
            raise HTTPException(status_code=500, detail="Azure credentials not initialized.")

        resource_client = ResourceManagementClient(credential, current_subscription_id)
        groups = list(resource_client.resource_groups.list())
        return [{"name": group.name, "location": group.location, "resource_count": 0} for group in groups]
    except Exception as e:
        logger.error(f"Failed to get resource groups: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/resource-groups/{resource_group_name}/resources")
async def list_resources_in_resource_group(resource_group_name: str, subscription_id: str | None = None):
    """
    List all resources within a specific resource group.
    """
    try:
        logger.info(f"Listing resources in resource group: {resource_group_name}")
        current_subscription_id = subscription_id
        
        if not current_subscription_id:
            try:
                account_info_output, account_returncode = run_azure_cli_command(['account', 'show'])
                if account_returncode == 0 and isinstance(account_info_output, dict) and account_info_output.get("id"):
                    current_subscription_id = account_info_output["id"]
                    logger.info(f"Using default subscription from Azure CLI: {current_subscription_id}")
                else:
                    raise HTTPException(status_code=400, detail="Subscription ID is required or login to Azure CLI with a default subscription.")
            except Exception as cli_e:
                logger.error(f"Error getting default subscription from Azure CLI: {cli_e}")
                raise HTTPException(status_code=500, detail=f"Could not determine default subscription: {str(cli_e)}")

        if not credential:
            raise HTTPException(status_code=500, detail="Azure credentials not initialized.")

        resource_client = ResourceManagementClient(credential, current_subscription_id)
        
        # Get resources within the specified resource group
        resources = list(resource_client.resources.list_by_resource_group(resource_group_name))
        
        # Transform to a simplified format
        result = []
        for resource in resources:
            resource_dict = {
                "id": resource.id,
                "name": resource.name,
                "type": resource.type,
                "location": resource.location if hasattr(resource, 'location') else None,
                "tags": resource.tags if hasattr(resource, 'tags') else None,
                "properties": {}
            }
            
            # Extract resource provider and resource type for icon assignment
            resource_type_parts = resource.type.split('/')
            provider = resource_type_parts[0].split('.')[-1] if len(resource_type_parts) > 0 else ""
            resource_type = resource_type_parts[1] if len(resource_type_parts) > 1 else ""
            # Assign appropriate icon based on resource type
            icon = "box"  # Default icon
            if provider.lower() == "compute":
                if resource_type.lower() in ["virtualmachines", "virtualmachinescalesets"]:
                    icon = "pc-display"
            elif provider.lower() == "storage":
                if resource_type.lower() == "storageaccounts":
                    icon = "hdd-stack"
            elif provider.lower() == "web":
                if resource_type.lower() == "sites":
                    icon = "globe"
            elif provider.lower() == "network":
                if resource_type.lower() == "virtualnetworks":
                    icon = "diagram-3"
                elif resource_type.lower() == "networkinterfaces":
                    icon = "ethernet"
                elif resource_type.lower() == "publicipaddresses":
                    icon = "globe"
                elif resource_type.lower() == "networksecuritygroups":
                    icon = "shield-lock"
            elif provider.lower() == "keyvault":
                if resource_type.lower() == "vaults":
                    icon = "key"
            elif provider.lower() == "documentdb":
                if resource_type.lower() == "databaseaccounts":
                    icon = "server"
            elif provider.lower() == "insights":
                icon = "graph-up"
            resource_dict["icon"] = icon
            result.append(resource_dict)
        
        logger.info(f"Found {len(result)} resources in resource group {resource_group_name}")
        return {"resources": result}
        
    except Exception as e:
        logger.error(f"Failed to list resources in resource group {resource_group_name}: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/resource-groups/{resource_group_name}")
async def delete_resource_group(resource_group_name: str, subscription_id: str | None = None):
    """
    Delete a resource group and all its contained resources.
    This is a destructive operation that cannot be undone.
    """
    try:
        logger.info(f"Initiating deletion of resource group: {resource_group_name}")
        current_subscription_id = subscription_id
        
        if not current_subscription_id:
            try:
                account_info_output, account_returncode = run_azure_cli_command(['account', 'show'])
                if account_returncode == 0 and isinstance(account_info_output, dict) and account_info_output.get("id"):
                    current_subscription_id = account_info_output["id"]
                    logger.info(f"Using default subscription from Azure CLI: {current_subscription_id}")
                else:
                    raise HTTPException(status_code=400, detail="Subscription ID is required or login to Azure CLI with a default subscription.")
            except Exception as cli_e:
                logger.error(f"Error getting default subscription from Azure CLI: {cli_e}")
                raise HTTPException(status_code=500, detail=f"Could not determine default subscription: {str(cli_e)}")

        if not credential:
            raise HTTPException(status_code=500, detail="Azure credentials not initialized.")

        resource_client = ResourceManagementClient(credential, current_subscription_id)
        
        # Check if resource group exists before attempting deletion
        try:
            resource_client.resource_groups.get(resource_group_name)
        except Exception as e:
            if "ResourceGroupNotFound" in str(e) or "not found" in str(e).lower():
                logger.warning(f"Resource group {resource_group_name} not found for deletion")
                raise HTTPException(status_code=404, detail=f"Resource group '{resource_group_name}' not found")
            else:
                logger.error(f"Error checking resource group existence: {str(e)}")
                raise HTTPException(status_code=500, detail=f"Error checking resource group: {str(e)}")
        
        # Initiate async deletion (resource group deletion is always async in Azure)
        delete_operation = resource_client.resource_groups.begin_delete(resource_group_name)
        
        # Log the deletion initiation
        logger.info(f"Resource group {resource_group_name} deletion initiated successfully. Operation status: {delete_operation.status()}")
        
        return {
            "status": "accepted", 
            "message": f"Resource group '{resource_group_name}' deletion initiated",
            "resource_group": resource_group_name,
            "subscription_id": current_subscription_id,
            "operation_status": delete_operation.status()
        }
        
    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except Exception as e:
        logger.error(f"Failed to delete resource group {resource_group_name}: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to delete resource group: {str(e)}")

# Exception handlers
@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {str(exc)}")
    return JSONResponse(
        status_code=500,
        content={"message": "An unexpected error occurred", "detail": str(exc)}
    )

@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException):
    logger.error(f"HTTP exception: {str(exc.detail)}")
    return JSONResponse(
        status_code=exc.status_code,
        content={"message": str(exc.detail)}
    )

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    logger.error(f"Validation error: {str(exc)}")
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={"message": "Validation error", "detail": exc.errors()}
    )

@app.exception_handler(ClientAuthenticationError)
async def auth_exception_handler(request: Request, exc: ClientAuthenticationError):
    logger.error(f"Authentication error: {str(exc)}")
    return JSONResponse(
        status_code=status.HTTP_401_UNAUTHORIZED,
        content={"message": "Authentication failed", "detail": str(exc)}
    )