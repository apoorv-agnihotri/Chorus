"""Embed required Swift compatibility libraries and remove build-machine rpaths."""
from pathlib import Path
import subprocess
import sys

app = Path(sys.argv[1])
executable = app / 'Contents/MacOS/Chorus'
frameworks = app / 'Contents/Frameworks'
frameworks.mkdir(exist_ok=True)
subprocess.run([
    'xcrun', 'swift-stdlib-tool', '--copy', '--scan-executable', str(executable),
    '--platform', 'macosx', '--destination', str(frameworks), '--sign', '-'
], check=True)
for backup in frameworks.glob('*.dylib.original'):
    backup.unlink()
output = subprocess.check_output(['otool', '-l', str(executable)], text=True)
rpaths = []
lines = output.splitlines()
for index, line in enumerate(lines):
    if line.strip() == 'cmd LC_RPATH':
        for entry in lines[index + 1:index + 4]:
            if entry.strip().startswith('path '):
                rpaths.append(entry.strip().split(' (offset', 1)[0][5:])
portable = '@executable_path/../Frameworks'
if portable not in rpaths:
    subprocess.run(['install_name_tool', '-add_rpath', portable, str(executable)], check=True)
for path in rpaths:
    if path.startswith(('/Library/Developer/', '/Applications/Xcode')):
        subprocess.run(['install_name_tool', '-delete_rpath', path, str(executable)], check=True)
