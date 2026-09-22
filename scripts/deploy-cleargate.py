"""Run on the existing cleargate host after uploading the tested static archive.

First publication only. Refuses an existing target or changed nginx config.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

archive = Path(sys.argv[1]).resolve()
expected_archive_hash = sys.argv[2]
release_id = sys.argv[3]
if not release_id.isalnum():
    raise SystemExit('Invalid release id')
if hashlib.sha256(archive.read_bytes()).hexdigest() != expected_archive_hash:
    raise SystemExit('Archive hash mismatch')
config = Path('/etc/nginx/nginx.conf')
original = config.read_bytes()
if hashlib.sha256(original).hexdigest() != '928e583ef39f053cad3dc334e3e3e0f692584108b110c2371cccebf9b3940d4f':
    raise SystemExit('Nginx changed since inspection; inspect again')
target = Path('/var/www/training')
if target.exists() or target.is_symlink():
    raise SystemExit('Training target already exists')
release = Path('/var/www/training-releases') / release_id
release.mkdir(parents=True, exist_ok=False)
with tarfile.open(archive, 'r:gz') as tar:
    for member in tar.getmembers():
        destination = (release / member.name).resolve()
        if not destination.is_relative_to(release) or member.issym() or member.islnk() or not (member.isfile() or member.isdir()):
            raise SystemExit('Unsafe archive entry')
    tar.extractall(release, filter='data')
for name in ('index.html','sw.js','manifest.webmanifest','icon-192.png','icon-512.png'):
    if not (release / name).is_file():
        raise SystemExit('Incomplete release')
for item in release.rglob('*'):
    item.chmod(0o755 if item.is_dir() else 0o644)
release.chmod(0o755)
needle = '        location = /fish {\n'
text = original.decode()
if text.count(needle) != 1 or '/training/' in text:
    raise SystemExit('Unexpected nginx structure')
block = '''        location = /training/manifest.webmanifest {
            root /var/www;
            default_type application/manifest+json;
            add_header Cache-Control "no-cache";
        }

        location = /training {
            return 301 /training/;
        }

        location ^~ /training/ {
            root /var/www;
            index index.html;
            try_files $uri $uri/ =404;
            add_header Cache-Control "no-cache";
            add_header X-Content-Type-Options "nosniff" always;
        }

'''
backup = config.with_name('nginx.conf.before-training-' + release_id)
candidate = config.with_name('nginx.conf.training-' + release_id)
if backup.exists() or candidate.exists():
    raise SystemExit('Backup/candidate already exists')
shutil.copy2(config, backup)
candidate.write_text(text.replace(needle, block + needle))
subprocess.run(['nginx','-t','-c',str(candidate)],check=True)
target.symlink_to(release, target_is_directory=True)
try:
    # Recheck immediately before replacing shared configuration.
    if config.read_bytes() != original:
        raise RuntimeError('Concurrent nginx change')
    os.replace(candidate,config)
    subprocess.run(['nginx','-t'],check=True)
    subprocess.run(['systemctl','reload','nginx'],check=True)
except Exception:
    if config.read_bytes() == (text.replace(needle, block + needle)).encode():
        shutil.copy2(backup,config)
        subprocess.run(['systemctl','reload','nginx'],check=True)
    if target.is_symlink() and target.resolve() == release:
        target.unlink()
    raise
print('Published: https://cleargate.ru/training/')
print('Rollback configuration:',backup)
print('Release:',release)
