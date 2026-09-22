import datetime, pathlib, sqlite3, tarfile, tempfile, os
os.umask(0o077)
source=pathlib.Path('/var/lib/traininglog')
backups=pathlib.Path('/var/backups/traininglog')
backups.mkdir(mode=0o700,parents=True,exist_ok=True)
name=datetime.datetime.now(datetime.timezone.utc).strftime('traininglog-%Y%m%dT%H%M%S.tar.gz')
with tempfile.TemporaryDirectory(dir=backups) as tmp:
    dbpath=pathlib.Path(tmp)/'training.db'
    with sqlite3.connect(f'file:{source}/training.db?mode=ro',uri=True) as src, sqlite3.connect(dbpath) as dst:
        src.backup(dst)
        assert dst.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    src.close();dst.close()
    target=backups/name
    with tarfile.open(target,'w:gz') as archive:
        archive.add(dbpath,arcname='training.db')
        archive.add(source/'keys',arcname='keys')
    pending=backups/'latest-next.tar.gz'
    if pending.is_symlink(): pending.unlink()
    pending.symlink_to(name)
    os.replace(pending,backups/'latest.tar.gz')
# Keep 30 snapshots, all deletions confined to this backup directory.
for old in sorted(backups.glob('traininglog-*.tar.gz'),reverse=True)[30:]:
    if old.is_file() and old.resolve().parent==backups.resolve(): old.unlink()
print(target)
