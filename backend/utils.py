import os
import json
import logging
import shutil
import subprocess

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
