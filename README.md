# What's in here?

On-The-Fly backups stop writing backups to your storage before it gets uploaded. That extends the life of SSDs and SD-Cards.


# Features
 - Very small foodprint (~20MByte)
 - Describe backup strategy
 - Validates backup strategy
 - Clear environment variable naming
 - Can be run without Docker
 - Send metrics to InfluxDB
 - *Docker*
   - Set behaviour by Docker-Labels
     - Stop container before and Start it after backup
     - Filter treated Containers by Group-Name
   - Backup all Images   
 - *Backup*
   - Follow Backup-Strategy (@see [https://de.wikipedia.org/wiki/Datensicherung#Backupstrategien](https://de.wikipedia.org/wiki/Datensicherung#Backupstrategien))
   - Create simple archives 
   - Create iterative Backups
   - Rotate Backup-Files
   - Backup To Archive first - short downtime for stopped services/container (1st: Archive,  2nd: Compress > Encrypt > Upload)
   - Backup On-The-Fly (Archive > Compress > Encrypt > Upload)
   - Include targets
     - Filesystem 
     - SSH
       - PKI Authentification
       - Pre/Post-Command   
 - *Restore*
   - List Backups
   - Restore On-The-Fly
 - *Customize Internals*
    - Use your favorite compression (Pipe + Extension)
    - Use your favorite encryption (Pipe + Extension)
    - Use your favorite Docker-Labels
    - Create own target (@see backup-target-ssh.sh)

### Docker-Container
- Run by crond
- Send notification (Mail, Telegram, Pushover...) - (@see [https://github.com/containrrr/shoutrrr](https://containrrr.dev/shoutrrr/latest/services/email/))

# Examples

***Describe Backup Procedure***
```shell
foo@bar:~$ docker exec -it docker-volume-backup /root/backup-strategy-describe.sh "i1 7 4 6*2"

Normalized backup strategy definition:
        i1*7 7*4 4*6 6*2 (given: i1 7 4 6*2)

Describe backup strategy:
        i1*7    => Backup - changes - every 1. days and keep last 7 backups for 7 days (1 copies)
        7*4     => Backup every 7. days and keep last 4 backups for 28 days (4 copies)
        4*6     => Backup every 28. days and keep last 6 backups for 168 days (6 copies)
        6*2     => Backup every 168. days and keep last 2 backups for 336 days (2 copies)

Examples for storage usage for whole period:
        13 Backups * 10 MB      => 130 MB / 0.13 GB
        13 Backups * 100 MB     => 1300 MB / 1.27 GB
        13 Backups * 1 GB       => 13312 MB / 13.00 GB / 0.01 TB
        13 Backups * 10 GB      => 133120 MB / 130.00 GB / 0.13 TB
        13 Backups * 20 GB      => 266240 MB / 260.00 GB / 0.25 TB
        13 Backups * 40 GB      => 532480 MB / 520.00 GB / 0.51 TB
        13 Backups * 80 GB      => 1064960 MB / 1040.00 GB / 1.02 TB
        13 Backups * 100 GB     => 1331200 MB / 1300.00 GB / 1.27 TB
```

***Restore Backup***
```shell
foo@bar:~$ docker exec -it docker-volume-backup /root/backup-restore.sh

[INFO] Please pass filename from list to be restored
-rw-r--r-- 1 user group  39M Mar 14 21:49 backup-volume-i168r336-202300.tar.gz
drwxr-xr-x 8 user group 4.0K Mar 15 20:52 backup-volume-i1r7-202310
-rw-r--r-- 1 user group  39M Mar 14 21:49 backup-volume-i28r168-202302.tar.gz
-rw-r--r-- 1 user group  39M Mar 14 21:49 backup-volume-i7r28-202310.tar.gz

foo@bar:~$ docker exec -it docker-volume-backup /root/backup-restore.sh backup-volume-i7r28-202310.tar.gz
```

# General Settings

 - BACKUP_TARGET="ssh"
 - BACKUP_STRATEGY="0*10d"
 - BACKUP_ONTHEFLY="true"
 - BACKUP_ENCRYPT_PASSPHRASE=""
 - BACKUP_PRE_COMMAND=""
 - BACKUP_POST_COMMAND=""
 - BACKUP_FILENAME="${BACKUP_FILENAME_PREFIX}-%Y-%m-%dT%H-%M-%S"

***Metrics***

 - INFLUXDB_URL=""
 - INFLUXDB_DB=""
 - INFLUXDB_CREDENTIALS=""
 - INFLUXDB_MEASUREMENT="docker_volume_backup"

## Docker-Container

 - BACKUP_CRON_SCHEDULE="0 9 * * *" 
 - BACKUP_NOTIFICATION_URL=""
 - BACKUP_IMAGES="false"
 - BACKUP_GROUP=""

***Labels***

 - com.pietma.backup.container.stop-during
 - com.pietma.backup.container.exec-command-before=/bin/sh -c "echo 'working' && sleep 1 &&  echo 'done'"
 - com.pietma.backup.container.exec-command-after=/bin/sh -c "echo 'working' && sleep 1 &&  echo 'done'"
 - com.pietma.backup.group="What-Ever-You-Like"

## Customize Internal Settings

 - DOCKER_SOCK="/var/run/docker.sock"
 - BACKUP_COMPRESS_EXTENSION=".gz"
 - BACKUP_COMPRESS_PIPE="gzip"
 - BACKUP_DECOMPRESS_PIPE="gzip -d"
 - BACKUP_ENCRYPT_EXTENSION=".gpg"
 - BACKUP_ENCRYPT_PIPE="gpg --symmetric --cipher-algo aes256 --batch --passphrase \"${BACKUP_ENCRYPT_PASSPHRASE}\""
 - BACKUP_DECRYPT_PIPE="gpg --decrypt --batch --passphrase \"${BACKUP_ENCRYPT_PASSPHRASE}\""
 - BACKUP_SOURCES="/volumes"
 - BACKUP_LABEL_CONTAINER_STOP_DURING="com.pietma.backup.container.stop-during"
 - BACKUP_LABEL_CONTAINER_EXEC_COMMAND_BEFORE="com.pietma.backup.container.exec-command-before"
 - BACKUP_LABEL_CONTAINER_EXEC_COMMAND_AFTER="com.pietma.backup.container.exec-command-after"
 - BACKUP_LABEL_GROUP="com.pietma.backup.group"		
 - BACKUP_IMAGES_FILENAME_PREFIX="backup-image"
 - BACKUP_FILENAME_PREFIX="backup-volume"

## Targets Settings

***ssh***

 - SSH_PRE_COMMAND=""
 - SSH_POST_COMMAND=""
 - SSH_HOST=""
 - SSH_PORT="22"
 - SSH_USER=""
 - SSH_REMOTE_PATH="."
 
***filesystem***

 - BACKUP_FILESYSTEM_PATH="/backups"
 
 # What's up next?
  - [ ] Backup volumes by label (without dedicated volume mount)
    - [ ] Add Setting to backup all volumes - exception by labels - or backup specified volumes - by labels
  - [ ] Only stop containers which are backed up at that time
  - [ ] Configure docker-volume-backup completely by labels
  
  
  
