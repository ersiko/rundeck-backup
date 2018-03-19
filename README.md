# Rundeck Backup Script

Tool to backup/restore a rundeck instance

The operation is very easy. To make a backup, you just have to do it:
```
[root @ server ~] # ./rundeck-backup.sh backup rundeck.tar.gz
OK - backup finished successfully using /root/rundeck-backup.tar.gz
```
If we do not put anything back, the backup will be saved with the date of the day:

```
[root @ server ~] # ./rundeck-backup.sh backup
OK - backup finished successfully using /root/rundeck-backup-20130327.tar.gz
```
And to restore, as easy as:
```
[root @ server ~] # ./rundeck-backup.sh restore pathtofile
Rundeck service is not running, so jobs can not be restored. Do you want to start rundeck? (y/N) y
Starting rundeckd: [OK]
OK - restore finished successfully using /root/rundeck-backup-20130327.tar.gz
```
He also has other options to cover all the circumstances that have come to me:
```
[root @ server ~] # ./rundeck-backup.sh -h
rundeck_backup - v1.00
Copyleft (c) 2013 Tomàs Núñez Lirola under GPL License
This script deals with rundeck backup / recovery.

Usage: ./rundeck-backup.sh [OPTIONS ...] {backup | restore} [backup_file] | -h --help

Options:
-h | --help
Print detailed help
--exclude-config
Do not backup / restore config files
--exclude-projects
Do not backup / restore project definitions
--exclude-keys
Do not backup / restore ssh key files
--exclude-jobs
Do not backup / restore job definitions
--exclude-hosts
Do not backup / restore .ssh / known_hosts file
--include-logs
Include execution logs in the backup / restore procedure (they are excluded by default)
-c | --configdir
Change default rundeck config directory (/ etc / rundeck)
-u | --user
Change default rundeck user (rundeck)
-s | --service
```
Based on "Project website at http://blog.tomas.cat/ca/2013/03/27/eina-gestionar-els-backups-de-rundeck/"
