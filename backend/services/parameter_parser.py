"""
Template Parameter Parser

This module extracts parameters from infrastructure-as-code templates:
- Bicep files (.bicep)
- Terraform files (.tf)
- ARM templates (.json)

It parses parameter definitions, types, default values, descriptions,
and validation rules to enable dynamic form generation.
"""

import re
import json
from typing import Dict, List, Any, Optional, Union
from pathlib import Path
from enum import Enum
import logging

logger = logging.getLogger(__name__)


class ParameterType(str, Enum):
    """Parameter data types"""
    STRING = "string"
    INT = "int"
    BOOL = "bool"
    OBJECT = "object"
    ARRAY = "array"
    NUMBER = "number"
    MAP = "map"


class Parameter:
    """Represents a template parameter with all its metadata"""

    def __init__(
        self,
        name: str,
        param_type: ParameterType,
        description: Optional[str] = None,
        default: Any = None,
        required: bool = True,
        allowed_values: Optional[List[Any]] = None,
        min_value: Optional[Union[int, float]] = None,
        max_value: Optional[Union[int, float]] = None,
        min_length: Optional[int] = None,
        max_length: Optional[int] = None,
        pattern: Optional[str] = None,
        validation_message: Optional[str] = None
    ):
        self.name = name
        self.type = param_type
        self.description = description
        self.default = default
        self.required = required and (default is None)
        self.allowed_values = allowed_values
        self.min_value = min_value
        self.max_value = max_value
        self.min_length = min_length
        self.max_length = max_length
        self.pattern = pattern
        self.validation_message = validation_message

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        result = {
            "name": self.name,
            "type": self.type.value,
            "description": self.description,
            "required": self.required
        }

        if self.default is not None:
            result["default"] = self.default

        if self.allowed_values:
            result["allowed_values"] = self.allowed_values

        if self.min_value is not None:
            result["min_value"] = self.min_value

        if self.max_value is not None:
            result["max_value"] = self.max_value

        if self.min_length is not None:
            result["min_length"] = self.min_length

        if self.max_length is not None:
            result["max_length"] = self.max_length

        if self.pattern:
            result["pattern"] = self.pattern

        if self.validation_message:
            result["validation_message"] = self.validation_message

        return result

    def __repr__(self):
        return f"Parameter(name={self.name}, type={self.type}, required={self.required})"


class BicepParameterParser:
    """Parser for Bicep template parameters"""

    @staticmethod
    def parse(content: str) -> List[Parameter]:
        """
        Parse parameters from Bicep template content.

        Extracts:
        - param declarations
        - @description decorators
        - @allowed decorators
        - @minValue/@maxValue decorators
        - @minLength/@maxLength decorators
        - default values
        """
        parameters = []
        lines = content.split('\n')

        i = 0
        while i < len(lines):
            line = lines[i].strip()

            # Check for parameter declaration
            if line.startswith('param '):
                param = BicepParameterParser._parse_param_line(line, lines, i)
                if param:
                    parameters.append(param)

            i += 1

        return parameters

    @staticmethod
    def _parse_param_line(line: str, all_lines: List[str], line_index: int) -> Optional[Parameter]:
        """Parse a single parameter declaration with decorators"""

        # Extract decorators from previous lines
        description = None
        allowed_values = None
        min_value = None
        max_value = None
        min_length = None
        max_length = None

        # Look back for decorators
        j = line_index - 1
        while j >= 0 and (all_lines[j].strip().startswith('@') or all_lines[j].strip() == ''):
            decorator_line = all_lines[j].strip()

            if decorator_line.startswith('@description('):
                desc_match = re.search(r"@description\('([^']+)'\)", decorator_line)
                if not desc_match:
                    desc_match = re.search(r'@description\("([^"]+)"\)', decorator_line)
                if desc_match:
                    description = desc_match.group(1)

            elif decorator_line.startswith('@allowed(['):
                # Extract allowed values
                allowed_match = re.search(r'@allowed\(\[(.*?)\]\)', decorator_line, re.DOTALL)
                if allowed_match:
                    values_str = allowed_match.group(1)
                    # Parse individual values
                    allowed_values = []
                    for value in re.findall(r"'([^']+)'", values_str):
                        allowed_values.append(value)

            elif '@minValue(' in decorator_line:
                min_match = re.search(r'@minValue\((\d+)\)', decorator_line)
                if min_match:
                    min_value = int(min_match.group(1))

            elif '@maxValue(' in decorator_line:
                max_match = re.search(r'@maxValue\((\d+)\)', decorator_line)
                if max_match:
                    max_value = int(max_match.group(1))

            elif '@minLength(' in decorator_line:
                min_match = re.search(r'@minLength\((\d+)\)', decorator_line)
                if min_match:
                    min_length = int(min_match.group(1))

            elif '@maxLength(' in decorator_line:
                max_match = re.search(r'@maxLength\((\d+)\)', decorator_line)
                if max_match:
                    max_length = int(max_match.group(1))

            j -= 1

        # Parse the param line itself
        # Format: param <name> <type> [= <default>]
        param_match = re.match(r'param\s+(\w+)\s+(\w+)(?:\s*=\s*(.+))?', line)
        if not param_match:
            return None

        param_name = param_match.group(1)
        param_type_str = param_match.group(2)
        default_value_str = param_match.group(3)

        # Map Bicep types to ParameterType
        type_mapping = {
            'string': ParameterType.STRING,
            'int': ParameterType.INT,
            'bool': ParameterType.BOOL,
            'object': ParameterType.OBJECT,
            'array': ParameterType.ARRAY
        }

        param_type = type_mapping.get(param_type_str.lower(), ParameterType.STRING)

        # Parse default value
        default_value = None
        if default_value_str:
            default_value = BicepParameterParser._parse_default_value(
                default_value_str.strip(),
                param_type
            )

        return Parameter(
            name=param_name,
            param_type=param_type,
            description=description,
            default=default_value,
            required=(default_value is None),
            allowed_values=allowed_values,
            min_value=min_value,
            max_value=max_value,
            min_length=min_length,
            max_length=max_length
        )

    @staticmethod
    def _parse_default_value(value_str: str, param_type: ParameterType) -> Any:
        """Parse default value based on parameter type"""
        value_str = value_str.strip()

        # Remove function calls like resourceGroup().location
        if '(' in value_str:
            return None

        if param_type == ParameterType.STRING:
            # Remove quotes
            if value_str.startswith("'") and value_str.endswith("'"):
                return value_str[1:-1]
            return value_str

        elif param_type == ParameterType.INT:
            try:
                return int(value_str)
            except ValueError:
                return None

        elif param_type == ParameterType.BOOL:
            return value_str.lower() == 'true'

        elif param_type == ParameterType.OBJECT:
            # Handle empty object {}
            if value_str == '{}':
                return {}
            return None

        elif param_type == ParameterType.ARRAY:
            # Handle empty array []
            if value_str == '[]':
                return []
            return None

        return None


class TerraformParameterParser:
    """Parser for Terraform template variables"""

    @staticmethod
    def parse(content: str) -> List[Parameter]:
        """
        Parse variables from Terraform template content.

        Extracts:
        - variable declarations
        - type constraints
        - descriptions
        - default values
        - validation rules
        """
        parameters = []

        # Find all variable blocks using balanced brace matching
        # First find all variable declarations
        var_starts = [(m.start(), m.group(1)) for m in re.finditer(r'variable\s+"([^"]+)"\s*\{', content)]

        for start_pos, var_name in var_starts:
            # Find the matching closing brace
            brace_count = 0
            body_start = content.find('{', start_pos) + 1

            for i in range(body_start, len(content)):
                if content[i] == '{':
                    brace_count += 1
                elif content[i] == '}':
                    if brace_count == 0:
                        # Found the matching closing brace
                        var_body = content[body_start:i]
                        param = TerraformParameterParser._parse_variable_block(var_name, var_body)
                        if param:
                            parameters.append(param)
                        break
                    else:
                        brace_count -= 1

        return parameters

    @staticmethod
    def _parse_variable_block(name: str, body: str) -> Optional[Parameter]:
        """Parse a single variable block"""

        # Extract type
        type_match = re.search(r'type\s*=\s*(\w+)', body)
        param_type_str = type_match.group(1) if type_match else 'string'

        # Map Terraform types to ParameterType
        type_mapping = {
            'string': ParameterType.STRING,
            'number': ParameterType.NUMBER,
            'bool': ParameterType.BOOL,
            'map': ParameterType.MAP,
            'list': ParameterType.ARRAY,
            'object': ParameterType.OBJECT,
            'any': ParameterType.STRING
        }

        param_type = type_mapping.get(param_type_str.lower(), ParameterType.STRING)

        # Extract description
        desc_match = re.search(r'description\s*=\s*"([^"]+)"', body)
        description = desc_match.group(1) if desc_match else None

        # Extract default value - handle multi-line structures
        default_value = None
        if 'default' in body:
            # For maps and objects, match the entire block including braces
            if param_type in [ParameterType.MAP, ParameterType.OBJECT]:
                default_match = re.search(r'default\s*=\s*(\{[^}]*\})', body, re.DOTALL)
                if default_match:
                    default_str = default_match.group(1).strip()
                    default_value = TerraformParameterParser._parse_default_value(
                        default_str,
                        param_type
                    )
            # For arrays, match the entire list including brackets
            elif param_type == ParameterType.ARRAY:
                default_match = re.search(r'default\s*=\s*(\[[^\]]*\])', body, re.DOTALL)
                if default_match:
                    default_str = default_match.group(1).strip()
                    default_value = TerraformParameterParser._parse_default_value(
                        default_str,
                        param_type
                    )
            # For simple types, match until newline
            else:
                default_match = re.search(r'default\s*=\s*(.+?)(?:\n|$)', body)
                if default_match:
                    default_str = default_match.group(1).strip()
                    default_value = TerraformParameterParser._parse_default_value(
                        default_str,
                        param_type
                    )

        # Extract validation
        validation_pattern = None
        validation_message = None
        allowed_values = None

        # Check for contains([...]) validation (allowed values)
        contains_match = re.search(
            r'contains\(\s*\[(.*?)\]\s*,',
            body,
            re.DOTALL
        )
        if contains_match:
            values_str = contains_match.group(1)
            # Extract quoted values
            allowed_values = re.findall(r'"([^"]+)"', values_str)

        # Check for regex validation
        validation_match = re.search(
            r'validation\s*\{[^}]*condition\s*=\s*can\(regex\("([^"]+)"',
            body
        )
        if validation_match:
            validation_pattern = validation_match.group(1)

        error_msg_match = re.search(r'error_message\s*=\s*"([^"]+)"', body)
        if error_msg_match:
            validation_message = error_msg_match.group(1)

        return Parameter(
            name=name,
            param_type=param_type,
            description=description,
            default=default_value,
            required=(default_value is None),
            allowed_values=allowed_values,
            pattern=validation_pattern,
            validation_message=validation_message
        )

    @staticmethod
    def _parse_default_value(value_str: str, param_type: ParameterType) -> Any:
        """Parse default value based on parameter type"""
        value_str = value_str.strip()

        if param_type == ParameterType.STRING:
            # Remove quotes
            if value_str.startswith('"') and value_str.endswith('"'):
                return value_str[1:-1]
            return None

        elif param_type == ParameterType.NUMBER:
            try:
                if '.' in value_str:
                    return float(value_str)
                return int(value_str)
            except ValueError:
                return None

        elif param_type == ParameterType.BOOL:
            return value_str.lower() == 'true'

        elif param_type == ParameterType.MAP:
            # Try to parse maps
            if value_str.startswith('{'):
                try:
                    # Extract the map content including multi-line
                    # Remove newlines and extra spaces for parsing
                    map_content = value_str.strip()
                    if map_content == '{}':
                        return {}

                    # For maps with content, return a simple empty map as default
                    # The actual values will be shown in description or ignored
                    # This indicates a default exists (so not required)
                    if '}' in map_content:
                        return {}
                except:
                    pass
            return None

        elif param_type == ParameterType.ARRAY:
            if value_str.startswith('[') and value_str.endswith(']'):
                return []
            return None

        return None


class TemplateParameterParser:
    """Main parameter parser that detects template type and delegates"""

    @staticmethod
    def parse_file(file_path: str) -> List[Parameter]:
        """
        Parse parameters from a template file.

        Auto-detects template type based on file extension.
        """
        path = Path(file_path)

        if not path.exists():
            raise FileNotFoundError(f"Template file not found: {file_path}")

        content = path.read_text(encoding='utf-8')

        if path.suffix == '.bicep':
            return BicepParameterParser.parse(content)
        elif path.suffix == '.tf':
            return TerraformParameterParser.parse(content)
        elif path.suffix == '.json':
            # TODO: Implement ARM template parser
            logger.warning("ARM template parsing not yet implemented")
            return []
        else:
            logger.warning(f"Unsupported template type: {path.suffix}")
            return []

    @staticmethod
    def parse_content(content: str, template_type: str) -> List[Parameter]:
        """
        Parse parameters from template content string.

        Args:
            content: Template content
            template_type: 'bicep', 'terraform', or 'arm'
        """
        if template_type == 'bicep':
            return BicepParameterParser.parse(content)
        elif template_type == 'terraform':
            return TerraformParameterParser.parse(content)
        elif template_type == 'arm':
            # TODO: Implement ARM template parser
            logger.warning("ARM template parsing not yet implemented")
            return []
        else:
            raise ValueError(f"Unsupported template type: {template_type}")
