import argparse,pathlib,tarfile,sqlite3,uuid
parser=argparse.ArgumentParser(description='Restore a backup into a NEW offline directory. Never replaces the live database.')
parser.add_argument('archive');parser.add_argument('destination');args=parser.parse_args()
dest=pathlib.Path(args.destination).resolve()
if dest.exists(): raise SystemExit('Destination must not exist')
with tarfile.open(args.archive) as tf:
    for member in tf.getmembers():
        name=pathlib.PurePosixPath(member.name)
        if name.is_absolute() or '..' in name.parts or member.issym() or member.islnk() or not (member.isfile() or member.isdir()):raise SystemExit('Unsafe archive')
        if str(name)!='training.db' and name.parts[0]!='keys':raise SystemExit('Unexpected archive member')
    dest.mkdir(mode=0o700,parents=True)
    tf.extractall(dest,filter='data')
with sqlite3.connect(dest/'training.db') as db:
    assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    assert db.execute('SELECT COUNT(*) FROM AspNetUsers').fetchone()[0]==1
    old=db.execute("SELECT Value FROM Settings WHERE Id='generation'").fetchone()[0]
    new=str(uuid.uuid4());db.execute("UPDATE Settings SET Value=? WHERE Id='generation'",(new,));db.commit()
    assert old!=new
    print('Integrity OK; new database generation; documents:',db.execute('SELECT COUNT(*) FROM Documents').fetchone()[0])
db.close()
print('Restored offline to',dest)
