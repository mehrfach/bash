#!/bin/bash
#
# backup docker container(s) and volume to other host
#
source dockerbackup.conf

BACKUP_NAME='dockerbackup_daily'
BACKUP_PATH='/root/dockerbackup/$BACKUP_NAME'
BACKUP_HOST=''
BACKUPSCRIPT_PATH='/root'
BACKUPSCRIPT_FILENAME='dockerbackup.sh'

function dorestore(){
	for file in `ssh root@$BACKUP_HOST 'ls -f *.tar'`
	do
		container=${file#".tar"}
		echo "$container container restoring"
	done
}

function dobackup(){
        local CONTAINER=$1
        DOCKERPSFILE='dockerps.bak'
        DOCKERVOLFILE="$CONTAINER.vol"
        echo "$CONTAINER container starts backing up to host $BACKUP_HOST"

        echo $(docker ps) > $DOCKERPSFILE
        scp $DOCKERPSFILE root@$BACKUP_HOST:$BACKUP_PATH/$DOCKERPSFILE
                rm -f $DOCKERPSFILE

        echo "Stopping container"
        docker stop $CONTAINER

		VOLUME_EXISTS=$(docker inspect -f '{{ .Mounts }}' $CONTAINER)
        
        if [ "[]" == "$VOLUME_EXISTS" ]; then
                echo "No volume found, skipping."
        else
				CONTAINERVOLUME=$(docker inspect -f '{{ (index .Mounts 0).Source }}' $CONTAINER)
                echo "Found volume: $CONTAINERVOLUME"
                echo $CONTAINERVOLUME > $DOCKERVOLFILE
                ssh root@$BACKUP_HOST "mkdir -p $BACKUP_PATH/volume/$CONTAINER/"
                scp $DOCKERVOLFILE root@$BACKUP_HOST:$BACKUP_PATH/$DOCKERVOLFILE
                rm -f $DOCKERVOLFILE

                echo "Start volume transfer"
                sudo rsync -rz $CONTAINERVOLUME/ root@$BACKUP_HOST:$BACKUP_PATH/volume/$CONTAINER/
        fi

        docker commit $CONTAINER $CONTAINER
        CONTAINERTARFILE="$1.tar"
        echo "Start backing up container to tar file: $CONTAINERTARFILE"
        docker save $CONTAINER -o $CONTAINERTARFILE
        echo "Start transfering tar file"
        scp $CONTAINERTARFILE root@$BACKUP_HOST:$BACKUP_PATH/$CONTAINERTARFILE
        rm -f $CONTAINERTARFILE
        echo "starting container again"
        docker start $CONTAINER
        echo "backup completed"

}

if [[ -z $BACKUP_NAME ]]; then echo "Variable BACKUP_NAME is missing in config file."; exit; fi
if [[ -z $BACKUP_PATH ]]; then echo "Variable BACKUP_PATH is missing in config file."; exit; fi
if [[ -z $BACKUP_HOST ]]; then echo "Variable BACKUP_HOST is missing in config file."; exit; fi
if [[ -z $BACKUPSCRIPT_PATH ]]; then echo "Variable BACKUPSCRIPT_PATH is missing in config file."; exit; fi
if [[ -z $BACKUPSCRIPT_FILENAME ]]; then echo "Variable BACKUPSCRIPT_FILENAME is missing in config file."; exit; fi

echo "finish here."
exit;

if [[ -z $1 ]] || [[ ("$1" != "backup") && ("$1" != "restore") ]]; then
        echo "Please choose option backup or restore as first argument"; exit
fi

if [[ "$1" == "backup" ]]; then
        if [[ -z $2 ]]; then
						echo "Delete backup directory on remote machine"
						ssh root@$BACKUP_HOST "rm -f -r $BACKUP_PATH/"

						echo "Backup this script to remote host - validating remote host connection!"
						ssh root@$BACKUP_HOST "mkdir -p $BACKUP_PATH/"
						scp $BACKUPSCRIPT_PATH/$BACKUPSCRIPT_FILENAME root@$BACKUP_HOST:$BACKUP_PATH/$BACKUPSCRIPT_FILENAME
		
                        containers=$(sudo docker ps | awk '{if(NR>1) print $NF}')
                        for containerName in $containers
                        do
                                        #echo "dobackup $containerName"
                                        dobackup $containerName
                                        echo ================================
                        done
        else
                        dobackup $2
        fi
fi

if [[ "$1" == "restore" ]]; then
		dorestore $2
fi
