# Setup

## SSH
* User has to be in sudoers wheel
* sudo needs ssh connection to server with config
```bash
sudo ssh raijin
```

## Copy client file
```bash
sudo mkdir -p /usr/local/bin/borgetmenot
sudo cp borgetmenot_client.sh /usr/local/bin/borgetmenot/borgetmenot_client.sh
```

## Make environment
```bash
mkdir -p /home/$(whoami)/botgetmenot_files
mkdir -p /var/log/borgetmenot
```

## Mail client
user needs to send email via msmtp

# Init borg repo

```bash
borg init --encryption=keyfile-blake2 raijin:/mnt/data/ALLBACKUP/BORGETMENOT/repos/<machine_name>
```

Make sure to backup keyfile and passphrase!!



