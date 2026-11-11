import shutil
import subprocess
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from web_gl import patched_source

class WebGLBridge(unittest.TestCase):
    def test_unexpected_template_is_rejected(self):
        with self.assertRaises(RuntimeError):
            patched_source('a newer or incomplete engine bridge')

    @unittest.skipUnless(shutil.which('node') and (ROOT/'build/web/index.js').is_file(),'requires a local Web build and Node')
    def test_exported_bridge_recycles_only_deleted_names(self):
        subprocess.run(['node',str(ROOT/'tools/check_web_gl.cjs'),str(ROOT/'build/web/index.js')],check=True,capture_output=True,text=True)
