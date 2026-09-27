"""Generate standard Flutter Android wrapper, then apply our native adapter.
Run once after checkout, on Windows/macOS/Linux with Flutter installed.
The overlay is authoritative; no developer SDK paths or signing secrets are committed.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

flutter=shutil.which('flutter')
if not flutter: raise SystemExit('Flutter SDK is required. Add flutter/bin to PATH.')
root=Path(__file__).resolve().parents[1]
if not (root/'android/gradlew').exists():
    with tempfile.TemporaryDirectory(prefix='osmo360-android-') as tmp:
        project=Path(tmp)/'shell_app'
        subprocess.run([flutter,'create','--no-pub','--platforms=android','--org=jp.hossie','--project-name=osmo360_shutter_app','--android-language=kotlin',str(project)],check=True)
        shutil.copytree(project/'android',root/'android',dirs_exist_ok=True)
shutil.copytree(root/'android_src',root/'android',dirs_exist_ok=True)
assets=root/'android/app/src/main/assets';assets.mkdir(parents=True,exist_ok=True)
shutil.copy(root/'web/map.html',assets/'map.html')
print('Android wrapper and native BLE/sensor/GPS adapter ready.')
