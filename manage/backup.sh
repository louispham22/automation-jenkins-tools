#!/bin/bash

: ${DATA_DIR:=/data}
: ${BACKUP_DIR:=/backup}
: ${REG_DIR:=/registry}

: ${BACKUP_GERRIT:=$DATA_DIR/gerrit}
: ${BACKUP_DOCKER:=$REG_DIR}

set +e
set -x
exitstatus=0

DATE=$(date +%y%m%d%H%M%S)

#Gerrit
BACKUP_DIR_GERRITDB=${BACKUP_DIR}/gerrit-db
if [ ! -d "${BACKUP_DIR_GERRITDB}" ]; then
    mkdir -p "${BACKUP_DIR_GERRITDB}";
fi
gerrit_db=gerrit-${DATE}.sql.gz
{
    find ${BACKUP_DIR_GERRITDB} -type f -maxdepth 1 -iname 'gerrit-*' -ctime +2|sort -r|tail -n+4| xargs --no-run-if-empty rm;
    docker exec gerrit_db_1 /bin/bash -c "mysqldump -uroot -prootpass --all-databases |gzip -9" > ${BACKUP_DIR_GERRITDB}/${gerrit_db} \
    && sleep 5;
} || exitstatus=1

BACKUP_DIR_GERRIT=${BACKUP_DIR}/gerrit
if [ ! -d "${BACKUP_DIR_GERRIT}" ]; then
    mkdir -p "${BACKUP_DIR_GERRIT}";
fi
{
    find ${BACKUP_DIR_GERRIT} -type d -maxdepth 1 -iname '[12]*' |sort -r | tail -n+7 | xargs --no-run-if-empty rm -rf;
    mkdir ${BACKUP_DIR_GERRIT}/${DATE} && \
        rsync -avz ${BACKUP_GERRIT}/app/git ${BACKUP_DIR_GERRIT}/${DATE}/
} || exitstatus=$(( $exitstatus + 2 ))

#other
BACKUP_DIR_OTHER=${BACKUP_DIR}/other
if [ ! -d "${BACKUP_DIR_OTHER}" ]; then
    mkdir -p "${BACKUP_DIR_OTHER}";
fi
other_data=other-${DATE}.tgz
{
    find ${BACKUP_DIR_OTHER} -type f -maxdepth 1 -iname 'other-*' -ctime +2|sort -r|tail -n+4| xargs --no-run-if-empty rm;
    docker exec -uroot $(hostname) /bin/bash -c "tar -zc -C /data dns ca slave-keys yum-repo" > ${BACKUP_DIR_OTHER}/${other_data} \
    && sleep 5;
} || exitstatus=$(( $exitstatus + 4 ));

#jenkins
BACKUP_DIR_JENKINS=${BACKUP_DIR}/jenkins
if [ ! -d "${BACKUP_DIR_JENKINS}" ]; then
    mkdir -p "${BACKUP_DIR_JENKINS}";
fi
jenkins=jenkins-backup-${DATE}.tgz
{
    find ${BACKUP_DIR_JENKINS} -type f -maxdepth 1 -iname 'jenkins-backup-*' -ctime +2|sort -r|tail -n+4| xargs --no-run-if-empty rm;
    docker exec -uroot $(hostname) /bin/bash -c "tar -zc --exclude=jenkins-hrbc/jobs/*/builds/*/archive --exclude=jenkins-hrbc/jobs/${JOB_NAME}/builds -C ${DATA_DIR} --warning=no-file-changed jenkins-hrbc" > ${BACKUP_DIR_JENKINS}/${jenkins};
    exitcode=$?;
    #tar return 1 in case of warnign and 0 in case of no warning. other codes are errors.
    if [ "$exitcode" != "1" ] && [ "$exitcode" != "0" ]; then
        exitstatus=$(( $exitstatus + 8 ));
    fi;
};

#registry
BACKUP_DIR_DOCKER=${BACKUP_DIR}/docker
if [ ! -d "${BACKUP_DIR_DOCKER}" ]; then
    mkdir -p "${BACKUP_DIR_DOCKER}";
fi
{
    find ${BACKUP_DIR_DOCKER} -type d -maxdepth 1 -iname '[12]*' |sort -r | tail -n+7 | xargs --no-run-if-empty rm -rf;
    mkdir ${BACKUP_DIR_DOCKER}/${DATE} && \
        rsync -avz ${BACKUP_DOCKER} ${BACKUP_DIR_DOCKER}/${DATE}/
} || exitstatus=$(( $exitstatus + 16 ))


#nexus
BACKUP_DIR_NEXUS=${BACKUP_DIR}/nexus
if [ ! -d "${BACKUP_DIR_NEXUS}" ]; then
    mkdir -p "${BACKUP_DIR_NEXUS}";
fi
nexus=nexus-backup-${DATE}.tgz
{
    find ${BACKUP_DIR_NEXUS} -type f -maxdepth 1 -iname 'nexus-backup-*' -ctime +2|sort -r|tail -n+4| xargs --no-run-if-empty rm;
    docker exec -uroot $(hostname) /bin/bash -c "tar -zc --exclude=nexus/log --exclude=nexus/tmp -C ${DATA_DIR} --warning=no-file-changed nexus" > ${BACKUP_DIR_NEXUS}/${nexus};
    exitcode=$?;
    #tar return 1 in case of warnign and 0 in case of no warning. other codes are errors.
    if [ "$exitcode" != "1" ] && [ "$exitcode" != "0" ]; then
        exitstatus=$(( $exitstatus + 32 ));
    fi;
};

exit $exitstatus