# What's in here?

On-The-Fly backups stop writing backups to your storage before it gets uploaded. That extends the life of SSDs and SD-Cards.


## General

 - Explains set backup procedure
 - Validates set backup procedure
 - Send metrics to InfluxDB
 - Override compression (Pipe + Extension)
 - Override encryption (Pipe + Extension)
 - Override backup target (@see backup-target-ssh.sh)
 - Prefixed environment variables
 - Start Stop containers
 - Works without docker
 
## Backup

 - Support Backup by strategy (@see https://de.wikipedia.org/wiki/Datensicherung#Backupstrategien)
 - Support Simple backup
 - Support Rotate backup-Files
 - Iterative Backups
 - Backup to Archive first, Compress And Upload Second (for little downtimes)
 - Support Backup On-The-Fly
 - Support Compress, Encrypt and Upload Backup On-The-Fly 
 - Support Backup Docker Images
 - Supported targets
  - SSH
   - PKI Authentification
   - Pre/Post-Command
 
## Restore

 - On-The-Fly Restore

## Labels

 - com.pietma.backup.container.stop-during
 - com.pietma.backup.container.exec-command-before=/bin/sh -c "echo 'working' && sleep 1 &&  echo 'done'"
 - com.pietma.backup.container.exec-command-after=/bin/sh -c "echo 'working' && sleep 1 &&  echo 'done'"
 - com.pietma.backup.group="What-Ever-You-Like"
 
## Environment (defaults)

Backup settings

 - BACKUP_GROUP=""
 - BACKUP_TARGET="ssh"
 - BACKUP_CRON_SCHEDULE="0 9 * * *" 
 - BACKUP_STRATEGY="0*10d"
 - BACKUP_PRE_COMMAND=""
 - BACKUP_POST_COMMAND=""
 - BACKUP_ONTHEFLY="true"
 - BACKUP_IMAGES="false"
 - BACKUP_ENCRYPT_PASSPHRASE=""

Filenames

 - BACKUP_FILENAME_PREFIX="backup-volume"
 - BACKUP_FILENAME="${BACKUP_FILENAME_PREFIX}-%Y-%m-%dT%H-%M-%S"
 - BACKUP_IMAGES_FILENAME_PREFIX="backup-image"

Metrics

 - INFLUXDB_URL=""
 - INFLUXDB_DB=""
 - INFLUXDB_CREDENTIALS=""
 - INFLUXDB_MEASUREMENT="docker_volume_backup"

## Targets
### ssh (BACKUP_TARGET="ssh")

 - SSH_PRE_COMMAND=""
 - SSH_POST_COMMAND=""
 - SSH_HOST=""
 - SSH_PORT="22"
 - SSH_USER=""
 - SSH_REMOTE_PATH="."
 
### filesystem (BACKUP_TARGET="filesystem")

 - BACKUP_FILESYSTEM_PATH="/backups"

### Customization Internals

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
 
 # What's up next?
  - [ ] Backup volumes by label (without dedicated mount)
   - [ ] Add Setting to backup all volumes - exception by labels - or backup specified volumes - by labels
  - [ ] Only stop containers which are backed up at the moment
  
  
  
