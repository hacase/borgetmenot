# Setup

## SSH
* User has to be in sudoers wheel
* sudo needs ssh connection to server with config
```bash
sudo ssh raijin
```

## Edit client file
```bash
mkdir -p /usr/local/bin/borgetmenot
cp borgetmenot_client.sh /usr/local/bin/borgetmenot/conf/borgetmenot_<client>.sh
```

## Make environment
```bash
mkdir -p /home/$(whoami)/botgetmenot_files
mkdir -p /var/log/borgetmenot
```

## Mail client
user needs to send email via msmtp

# Init borg repo

Create as root, if not change the keyfile directory accordingly.
```bash
borg init --encryption=keyfile-blake2 raijin:/mnt/data/ALLBACKUP/BORGETMENOT/repos/<client>
```

Make sure to backup keyfile and passphrase!!

## Passfile

Store passfile to default location ```/usr/local/bin/borgetmenot/borgetmenot_<client>.txt```.
Set permission
```bash
chmod 600 /usr/local/bin/borgetmenot/borgetmenot<client>.txt
```

## Keyfile

Keyfile should be here by borg default if created by root
```bash
chmod 600 /root/.config/borg/keys/<client>
chmod 700 /root/.config/borg/keys/
```
