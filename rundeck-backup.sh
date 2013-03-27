#!/bin/bash

RUNDECK_USER=rundeck
RUNDECK_CONFIG_DIR=/etc/rundeck
RUNDECK_SERVICE=rundeckd
TMPDIR=/tmp
DEFAULT_BACKUP_FILE=rundeck-backup-`date +%Y%m%d`.tar.gz


function usage {
echo "Usage: $0 [OPTIONS...] {backup|restore} [backup_file] | -h --help"
}

function areyousure {
    read -p "$1" bool
    [ "$bool" != "y" ] && echo "Ok, aborting..." && exit 0
}

function backup {
  [ -d "${backup_file}" ] && backup_file="${backup_file}/${DEFAULT_BACKUP_FILE}"
  [ -f "${backup_file}" ] && [ -z ${force} ] && areyousure "${backup_file} already exists. Overwrite? (y/N) " 
  
  [ -d ${BACKUPDIR} ] && echo "Directory ${BACKUPDIR} already exists. Aborting" && exit 1
  mkdir -p ${BACKUPDIR}
  [ ! -d ${BACKUPDIR} ] && echo "Couldn't create ${BACKUPDIR}. Aborting" && exit 1

  # Rundeck config
  if [ -z "$exclude_config" ];then
    cp -a ${RUNDECK_CONFIG_DIR} ${BACKUPDIR}
    [ $? -ne 0 ] && errors_config=1   
  fi

  # Project definitions
  PROJECTS_VALUE=`grep ^project.dir ${RUNDECK_CONFIG_DIR}/project.properties|cut -d "=" -f 2`
  PROJECTS_DIR=`dirname ${PROJECTS_VALUE}`
  if [ -z "${exclude_projects}" ];then
    cp -a ${PROJECTS_DIR} ${BACKUPDIR}
    [ $? -ne 0 ] && errors_projects=1
  fi

  # Project keys  
  if [ -z "${exclude_keys}" ];then
    for project in ${PROJECTS_DIR}/*;do 
      mkdir -p ${BACKUPDIR}/keys/`basename ${project}`
      key=`grep project.ssh-keypath ${project}/etc/project.properties|cut -d"=" -f 2`
      cp ${key} ${key}.pub ${BACKUPDIR}/keys/`basename ${project}`
      [ $? -ne 0 ] && errors_keys=1 
    done
  fi

  # Job definitions
  if [ -z "${exclude_jobs}" ];then
    service ${RUNDECK_SERVICE} status > /dev/null  
    if [ $? -ne 0 ] && [ -z ${force} ];then
      areyousure "Rundeck service is not running, so jobs can't be exported. Do you want to start rundeck? (y/N) "
      service ${RUNDECK_SERVICE} start
      sleep 60
      service ${RUNDECK_SERVICE} status > /dev/null  
      [ $? -ne 0 ] && echo  "Rundeck could not start. Aborting..."
    fi
    mkdir -p ${BACKUPDIR}/jobs
    for project in ${PROJECTS_DIR}/*;do rd-jobs list -f ${BACKUPDIR}/jobs/`basename ${project}.xml` -p `basename ${project}` > /dev/null
    [ $? -ne 0 ] && errors_jobs=1;done
  fi

  # known_hosts
  if [ -z "${exclude_hosts}" ];then
    cp `getent passwd ${RUNDECK_USER}|cut -d":" -f6`/.ssh/known_hosts ${BACKUPDIR}
    [ $? -ne 0 ] && errors_hosts=1
  fi
  
  # execution logs
  if [ -n "${include_logs}" ];then
    cp -a `grep ^framework.logs.dir ${RUNDECK_CONFIG_DIR}/framework.properties |cut -d"=" -f 2` ${BACKUPDIR}
    [ $? -ne 0 ] && [ -n "${include_logs}" ] && errors_logs=1
  fi

  cd ${BACKUPDIR}
  tar zcf "${backup_file}" *
  [ $? -ne 0 ] && echo "Error creating tar file. Is there free space? Do you have permissions over this file?" && exit 1
  rm -rf ${BACKUPDIR}
}


function restore {
  
  service ${RUNDECK_SERVICE} status > /dev/null  
  [ $? -eq 0 ] && [ -z ${force} ] && areyousure "Rundeck service is running. It's recommended to stop it before restoring a backup. Do you want to continue? (y/N) "
  
  [ ! -f "${backup_file}" ] && echo "Error: file ${backup_file} not found" && usage && exit 1  
  [ -d ${BACKUPDIR} ] && echo "Directory ${BACKUPDIR} already exists. Aborting" && exit 1
  mkdir -p ${BACKUPDIR}
  [ ! -d ${BACKUPDIR} ] && echo "Unknown error. Couldn't create ${BACKUPDIR}. Aborting" && exit 1
  
  cd ${BACKUPDIR}
  tar zxf "${backup_file}"      
  [ $? -ne 0 ] && echo "ERROR - Could not unpack backup file. Maybe it's not a .tar.gz file, maybe there isn't enough free space, maybe you don't have permissions to write in ${BACKUPDIR}. Aborting ..." && exit 1

  # Rundeck config
  if [ -z "$exclude_config" ];then
    cp -a `basename ${RUNDECK_CONFIG_DIR}` `dirname ${RUNDECK_CONFIG_DIR}`
    [ $? -ne 0 ] && errors_config=1   
  fi

  # Project definitions
  configdir=`basename ${RUNDECK_CONFIG_DIR}`
  PROJECTS_VALUE=`grep ^project.dir $configdir/project.properties|cut -d "=" -f 2`
  PROJECTS_DIR=`dirname ${PROJECTS_VALUE}`
  if [ -z "${exclude_projects}" ];then
    cp -a projects/* ${PROJECTS_DIR}
    [ $? -ne 0 ] && errors_projects=1
  fi

  # Project keys
  if [ -z "${exclude_keys}" ];then
    for project in projects/*;do 
      key=`grep project.ssh-keypath ${project}/etc/project.properties|cut -d"=" -f 2`
      cp keys/`basename $project`/`basename ${key}` keys/`basename $project`/`basename ${key}`.pub `dirname ${key}`
      [ $? -ne 0 ] && errors_keys=1 
    done
  fi

  # Job definitions
  if [ -z "${exclude_jobs}" ];then
    service ${RUNDECK_SERVICE} status > /dev/null  
    [ $? -ne 0 ] && [ -z ${force} ] && areyousure "Rundeck service is not running, so jobs can't be restored. Do you want to start rundeck? (y/N) "
    service ${RUNDECK_SERVICE} start
    sleep 60
    service ${RUNDECK_SERVICE} status > /dev/null  
    [ $? -ne 0 ] && echo  "Rundeck could not start. Aborting..."
    for project in projects/*;do rd-jobs load -f jobs/`basename ${project}`.xml > /dev/null
    [ $? -ne 0 ] && errors_jobs=1;done
  fi
  
  # known_hosts
  if [ -z "${exclude_hosts}" ];then
    cp known_hosts `getent passwd ${RUNDECK_USER}|cut -d":" -f6`/.ssh/known_hosts
    [ $? -ne 0 ] && errors_hosts=1
  fi
  
  # execution logs
  if [ -n "${include_logs}" ];then
    cp -a logs/* `grep ^framework.logs.dir ${RUNDECK_CONFIG_DIR}/framework.properties |cut -d"=" -f 2`
    [ $? -ne 0 ] && [ -n "${include_logs}" ] && errors_logs=1
  fi

  rm -rf ${BACKUPDIR}  
}


args=`getopt -o hlc:fu:s: --long help,exclude-config,exclude-projects,exclude-keys,exclude-jobs,exclude-hosts,include-logs,configdir:,force,user:,service: -n $0 -- "$@"`
[ $? != 0 ] && echo "$0: Could not parse arguments" && usage && exit 1
eval set -- "$args"

while true ; do
        case "$1" in
                --exclude-config)    exclude_config=1;shift;;
                --exclude-projects)  exclude_projects=1;shift;;
                --exclude-keys)      exclude_keys=1;shift;;
                --exclude-jobs)      exclude_jobs=1;shift;;
                --exclude-hosts)     exclude_hosts=1;shift;;
                -l|--include-logs)   include_logs=1;shift;;
                -c|--configdir)      RUNDECK_CONFIG_DIR="$2";shift 2;;
                -u|--user)           RUNDECK_USER="$2";shift 2;;
                -s|--service)        RUNDECK_SERVICE="$2";shift 2;;
                -f|--force)          force=1;shift;;
                -h|--help)     echo "rundeck_backup - v1.00"
                               echo "Copyleft (c) 2013 Tomàs Núñez Lirola <tnunez@criptos.com> under GPL License"
                               echo "This script deals with rundeck backup/recovery."
                               echo ""
                               usage
                               echo ""
                               echo "Options:"
                               echo "-h | --help"
                               echo "     Print detailed help"
                               echo "--exclude-config"
                               echo "     Don't backup / restore config files"
                               echo "--exclude-projects"
                               echo "     Don't backup / restore project definitions"
                               echo "--exclude-keys"
                               echo "     Don't backup / restore ssh key files"
                               echo "--exclude-jobs"
                               echo "     Don't backup / restore job definitions"
                               echo "--exclude-hosts"
                               echo "     Don't backup / restore .ssh/known_hosts file"
                               echo "--include-logs"
                               echo "     Include execution logs in the backup / restore procedure (they are excluded by default)"
                               echo "-c <directory> | --configdir <directory>"
                               echo "     Change default rundeck config directory (/etc/rundeck)"
                               echo "-u <user> | --user <user>"
                               echo "     Change default rundeck user (rundeck)"
                               echo "-s <service> | --service <service"
                               echo "     Change default rundeck service (rundeckd)"
                               echo "-f | --force"
                               echo "     Assume 'yes' to all questions"
                               echo ""
                               echo "This plugin will backup or restore a rundeck instance, copying files and exporting job definitions with rd-jobs tool. "
                               echo "Examples:"
                               echo "     $0 backup rundeck-201303.tar.gz"
                               echo "     $0 restore --exclude-jobs rundeck-201303.tar.gz"
                               echo ""
                               exit;;
                --) shift; break;;
                *)  echo "Internal error!" ; exit 1 ;;
        esac
done

[ $# -lt 1 ] && echo "Error! Missing arguments" && usage && exit 1
action=$1
backup_file="${2:-$DEFAULT_BACKUP_FILE}"
backup_file=`readlink -m "$backup_file"`

[ -n "${exclude_config}" ] && [ -n "${exclude_projects}" ] && [ -n "${exclude_keys}" ] && [ -n "${exclude_jobs}" ] && [ -n "${exclude_hosts}" ] && [ -z "${include_logs}" ] && echo "Error! If everything is excluded, no action will be taken" && exit 1

ID=${RANDOM}
BACKUPDIR=/${TMPDIR}/rundeck-backup-$ID


if [ ${action} == "backup" ];then
  backup ${backup_file}
elif [ ${action} == "restore" ];then
  restore ${backup_file}
else 
  echo "Value $1 not recognized. Accepted values: backup, restore" && usage && exit 1
fi


[ -n "${errors_config}" ] && echo "Something happened when copying the config files. Backup may not be complete" 
[ -n "${errors_projects}" ] && echo "Something happened when copying the project definitions. Backup may not be complete" 
[ -n "${errors_keys}" ] && echo "Something happened when copying ssh key files. Backup may not be complete" 
[ -n "${errors_jobs}" ] && echo "Something happened when copying job definitions. Backup may not be complete" 
[ -n "${errors_hosts}" ] && echo "Something happened with the known_hosts file. Backup may not be complete" 
[ -n "${errors_logs}" ] && echo "Something happened with the execution log files. Backup may not be complete" 
[ -n "${errors_config}" ] || [ -n "${errors_projects}" ] || [ -n "${errors_keys}" ] || [ -n "${errors_jobs}" ] || [ -n "${errors_hosts}" ] || [ -n "${errors_logs}" ] && exit 2

echo "OK - ${action} finished successfully using ${backup_file}" 