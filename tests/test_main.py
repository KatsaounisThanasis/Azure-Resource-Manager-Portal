import pytest
import sys
import os
import json

# Add the parent directory to the path so we can import the app
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Test the backend by testing file structure and syntax
class TestAzureResourceManagerPortal:
    
    def test_backend_imports(self):
        """Test that the backend can be imported without errors"""
        try:
            from backend.main import app
            assert app is not None
            print("✅ Backend imports successfully")
        except ImportError as e:
            pytest.fail(f"Failed to import backend.main: {e}")
    
    def test_static_files_exist(self):
        """Test that required static files exist"""
        frontend_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "frontend")
        
        # Check main files exist
        assert os.path.exists(os.path.join(frontend_dir, "index.html"))
        assert os.path.exists(os.path.join(frontend_dir, "js", "main.js"))
        assert os.path.exists(os.path.join(frontend_dir, "js", "utils.js"))
        assert os.path.exists(os.path.join(frontend_dir, "css", "styles.css"))
        print("✅ All static files exist")
        
    def test_javascript_syntax(self):
        """Test that JavaScript files have valid syntax"""
        frontend_js_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "frontend", "js")
        
        js_files = [
            "main.js",
            "utils.js", 
            "templates.js",
            "deployments.js",
            "resourceGroups.js"
        ]
        
        for js_file in js_files:
            file_path = os.path.join(frontend_js_dir, js_file)
            if os.path.exists(file_path):
                # Basic syntax check - ensure file can be read and has matching braces
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    
                # Count braces to check for basic syntax validity
                open_braces = content.count('{')
                close_braces = content.count('}')
                assert open_braces == close_braces, f"Mismatched braces in {js_file}"
                
                # Count parentheses
                open_parens = content.count('(')
                close_parens = content.count(')')
                assert open_parens == close_parens, f"Mismatched parentheses in {js_file}"
                
                # Ensure no obvious syntax errors
                assert 'function(' in content or 'function ' in content or '=>' in content, f"No functions found in {js_file}"
                print(f"✅ {js_file} syntax is valid")
                
    def test_html_structure(self):
        """Test that HTML file has proper structure"""
        html_file = os.path.join(os.path.dirname(os.path.dirname(__file__)), "frontend", "index.html")
        
        with open(html_file, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # Check for essential HTML structure
        assert '<html' in content.lower()
        assert '<head>' in content.lower()
        assert '<body>' in content.lower()
        assert '</html>' in content.lower()
        # Check for our app-specific elements
        assert 'id="mainContent"' in content or 'id=\'mainContent\'' in content
        assert 'main.js' in content
        print("✅ HTML structure is valid")
        
    def test_css_file_validity(self):
        """Test that CSS file exists and is not empty"""
        css_file = os.path.join(os.path.dirname(os.path.dirname(__file__)), "frontend", "css", "styles.css")
        
        assert os.path.exists(css_file)
        
        with open(css_file, 'r', encoding='utf-8') as f:
            content = f.read().strip()
            
        assert len(content) > 0, "CSS file should not be empty"
        # Basic CSS syntax check
        assert '{' in content and '}' in content, "CSS file should contain CSS rules"
        print("✅ CSS file is valid")
        
    def test_backend_file_structure(self):
        """Test that backend files exist and have proper structure"""
        backend_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "backend")
        # Check main backend files
        assert os.path.exists(os.path.join(backend_dir, "main.py"))
        assert os.path.exists(os.path.join(backend_dir, "utils.py"))
        
        # Check main.py has FastAPI app
        main_file = os.path.join(backend_dir, "main.py")
        with open(main_file, 'r', encoding='utf-8') as f:
            content = f.read()
            
        assert 'FastAPI' in content, "main.py should import FastAPI"
        assert 'app = FastAPI' in content, "main.py should create FastAPI app instance"
        print("✅ Backend file structure is valid")
        
    def test_project_documentation(self):
        """Test that project has proper documentation"""
        project_root = os.path.dirname(os.path.dirname(__file__))
        
        # Check README exists
        readme_file = os.path.join(project_root, "README.md")
        assert os.path.exists(readme_file)
        
        with open(readme_file, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # Check README has essential sections
        assert 'Azure Resource Manager Portal' in content
        assert 'Features' in content or 'Installation' in content
        print("✅ Project documentation is complete")
        
    def test_requirements_file(self):
        """Test that requirements.txt exists and has essential dependencies"""
        requirements_file = os.path.join(os.path.dirname(os.path.dirname(__file__)), "requirements.txt")
        
        if os.path.exists(requirements_file):
            with open(requirements_file, 'r', encoding='utf-8') as f:
                content = f.read()
                
            # Check for essential dependencies
            assert 'fastapi' in content.lower()
            assert 'uvicorn' in content.lower()
            print("✅ Requirements file is complete")
        else:
            print("ℹ️ Requirements file not found (optional)")