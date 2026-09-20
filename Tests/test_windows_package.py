from pathlib import Path
import unittest, zipfile
class PackageTest(unittest.TestCase):
 def test_ready_to_run(self):
  p=Path('dist/ScreenPilot-Windows.zip')
  self.assertTrue(p.exists(), 'Missing ready-to-run Windows package')
  with zipfile.ZipFile(p) as z:
   binary=z.read('ScreenPilot/ScreenPilotBridge.exe')
   self.assertEqual(binary[:2],b'MZ')
   self.assertIn('ScreenPilot/开始使用.txt',z.namelist())
if __name__=='__main__': unittest.main()
