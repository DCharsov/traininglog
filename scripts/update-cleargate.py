import os, pathlib, shutil, tarfile, datetime, hashlib
base=pathlib.Path('/var/www/training-releases').resolve()
link=pathlib.Path('/var/www/training')
old=link.resolve(strict=True)
assert old.parent==base and link.is_symlink()
release=base/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S')
release.mkdir()
with tarfile.open('/root/traininglog-deploy/update.tar.gz') as tf:
    tf.extractall(release, filter='data')
assert (release/'index.html').is_file() and (release/'sw.js').is_file()
for asset in (old/'assets').iterdir():
    if asset.is_file() and not (release/'assets'/asset.name).exists():
        shutil.copy2(asset,release/'assets'/asset.name)
tmp=pathlib.Path('/var/www/training-next')
assert not tmp.exists() and not tmp.is_symlink()
tmp.symlink_to(release)
os.replace(tmp,link)
print('Previous:',old)
print('Published:',release)
print('Index SHA256:',hashlib.sha256((release/'index.html').read_bytes()).hexdigest())
