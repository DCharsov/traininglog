"""Update only TrainingLog API; retain prior release and back up data before switch."""
import datetime
import json
import os
import pathlib
import subprocess
import tarfile
import time
import urllib.request

os.umask(0o077)
root = pathlib.Path('/opt/traininglog')
releases = (root / 'releases').resolve()
current = root / 'current'
assert current.is_symlink(), 'Expected an existing TrainingLog installation'
previous = current.resolve(strict=True)
assert previous.parent == releases
release = releases / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S')
release.mkdir()
with tarfile.open(os.environ.get('TRAININGLOG_API_ARCHIVE', '/root/traininglog-deploy/api-update.tar.gz')) as archive:
    archive.extractall(release, filter='data')
assert (release / 'api').is_file() and (release / 'openapi.json').is_file()
(release / 'api').chmod(0o755)
subprocess.run(['chown', '-R', 'traininglog:traininglog', str(release)], check=True)
subprocess.run(['systemctl', 'start', 'traininglog-backup.service'], check=True)

def point_to(target):
    link = root / 'next-release'
    assert not link.exists() and not link.is_symlink()
    link.symlink_to(target)
    os.replace(link, current)

subprocess.run(['systemctl', 'stop', 'traininglog'], check=True)
try:
    point_to(release)
    subprocess.run(['systemctl', 'start', 'traininglog'], check=True)
    for attempt in range(30):
        try:
            with urllib.request.urlopen('http://127.0.0.1:5180/training/api/health', timeout=2) as response:
                assert json.load(response)['contractVersion'] == 2
            break
        except Exception:
            if attempt == 29:
                raise
            time.sleep(1)
except Exception:
    subprocess.run(['systemctl', 'stop', 'traininglog'], check=True)
    point_to(previous)
    subprocess.run(['systemctl', 'start', 'traininglog'], check=True)
    raise
print('API release:', release)
print('Previous release retained:', previous)
