import pathlib,os,tarfile,subprocess,shutil,datetime,time,urllib.request
os.umask(0o077)
root=pathlib.Path('/opt/traininglog');releases=root/'releases'
releases.mkdir(parents=True,exist_ok=True)
assert not (root/'current').exists(), 'First server installation only'
release=releases/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S')
release.mkdir()
with tarfile.open('/root/traininglog-deploy/api.tar.gz') as archive: archive.extractall(release,filter='data')
(release/'api').chmod(0o755)
# Service can read its own release; private data is kept outside code and web roots.
subprocess.run(['useradd','--system','--home-dir','/var/lib/traininglog','--shell','/usr/sbin/nologin','traininglog'],check=True)
data=pathlib.Path('/var/lib/traininglog');data.mkdir(mode=0o700)
shutil.copyfile('/root/traininglog-deploy/owner-password.txt',data/'initial-password')
subprocess.run(['chown','-R','traininglog:traininglog',str(data),str(root)],check=True)
(root/'current').symlink_to(release)
shutil.copyfile('/root/traininglog-deploy/server-backup.py',root/'server-backup.py')
unit='''[Unit]
Description=TrainingLog private API
After=network.target
[Service]
User=traininglog
Group=traininglog
WorkingDirectory=/opt/traininglog/current
ExecStart=/opt/traininglog/current/api --urls http://127.0.0.1:5180 --DataDirectory /var/lib/traininglog --OwnerPasswordFile /var/lib/traininglog/initial-password
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=Logging__LogLevel__Default=Warning
Environment=Logging__LogLevel__Microsoft=Warning
Restart=on-failure
RestartSec=5
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/traininglog
[Install]
WantedBy=multi-user.target
'''
pathlib.Path('/etc/systemd/system/traininglog.service').write_text(unit)
subprocess.run(['systemctl','daemon-reload'],check=True)
subprocess.run(['systemctl','enable','--now','traininglog'],check=True)
for attempt in range(30):
    try:
        with urllib.request.urlopen('http://127.0.0.1:5180/training/api/health') as r: assert r.status==200
        break
    except Exception:
        if attempt==29:raise
        time.sleep(1)
config=pathlib.Path('/etc/nginx/nginx.conf');original=config.read_text()
assert 'location ^~ /training/api/' not in original
anchor='        location = /training/manifest.webmanifest {'
assert original.count(anchor)==1
block='''        location ^~ /training/api/ {
            client_max_body_size 2m;
            proxy_pass http://127.0.0.1:5180;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 30s;
            proxy_connect_timeout 5s;
        }

'''
backup=pathlib.Path('/etc/nginx/nginx.conf.before-training-api-'+release.name)
shutil.copy2(config,backup)
assert config.read_text()==original
config.write_text(original.replace(anchor,block+anchor))
try:
    subprocess.run(['nginx','-t'],check=True)
    subprocess.run(['systemctl','reload','nginx'],check=True)
except Exception:
    config.write_text(original)
    raise
pathlib.Path('/etc/systemd/system/traininglog-backup.service').write_text('''[Unit]
Description=Consistent TrainingLog backup
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /opt/traininglog/server-backup.py
UMask=0077
''')
pathlib.Path('/etc/systemd/system/traininglog-backup.timer').write_text('''[Unit]
Description=Daily TrainingLog backup
[Timer]
OnCalendar=*-*-* 02:30:00 UTC
Persistent=true
[Install]
WantedBy=timers.target
''')
subprocess.run(['systemctl','daemon-reload'],check=True)
subprocess.run(['systemctl','enable','--now','traininglog-backup.timer'],check=True)
subprocess.run(['systemctl','start','traininglog-backup.service'],check=True)
# Bootstrap secret is no longer needed once Identity has created the owner.
(data/'initial-password').unlink()
pathlib.Path('/root/traininglog-deploy/owner-password.txt').unlink()
print('API release:',release)
print('Nginx backup:',backup)
