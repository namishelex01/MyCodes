#!/bin/bash

name=$2
instanceId=$1
region="ap-southeast-1"

function AllChecksDone {
	#########################################
	echo "[***] Check the arguments have been passed correctly"
	if [ -z "$name" ] || [ -z "$instanceId" ]
	then
			echo " "
			echo "Invalid arguments."
		echo " "
			exit 1
	fi
	#########################################
	verifyInstance=$(aws ec2 describe-instances --region "$region" --filters Name=instance-id,Values="$instanceId")
	verifyId=$(echo -e "$verifyInstance" | /usr/bin/jq '.Reservations[].Instances[].InstanceId' | tr -d '"')
	#########################################
	echo "[***] Verify the Instance Exist"
	if [ -z "$verifyId" ]
	then
			echo " "
			echo " Instance Id: $instanceId is not a valid Id"
		echo " "
			exit 1
	fi
}	

function GetEC2VolumeDetails {
	echo "[***] Capture EC2 volume details"
	volumes=$(aws ec2 describe-volumes --region "$region" --filters Name=attachment.instance-id,Values="$instanceId")
	#########################################
	volume_data=$(echo -e "$volumes" | /usr/bin/jq '.Volumes[].VolumeId' | tr -s '\n' ' ' | tr -d '"' | tr -s "[:space:]")
	attachment_details=$(echo -e "$volumes" | /usr/bin/jq '.Volumes[].Attachments[].Device' | tr -s '\n' ' ' | tr -d '"' | tr -s "[:space:]")
	#########################################
	echo "Volume Data: $volume_data"
	echo "Attachment Data: $attachment_details"
	#########################################
}

function CreateSnapshotFromVolume {
	echo "[***] Create Snapshot from Volume"
	snapshot_response=$(aws ec2 create-snapshot \
	  --volume-id $volume_data \
	  --description "A Snapshot for server $name" \
	  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value="$name"}]" \
	  --region "$region")
	#########################################
	snapshotId=$(echo -e "$snapshot_response" | /usr/bin/jq '.SnapshotId' | tr -d '"')
	#########################################
	response=1
	while [  "$response" -ne 0 ]; do
			echo "Waiting for Snapshot $snapshotId to become available...."
			aws ec2 wait snapshot-completed --snapshot-id "$snapshotId" --region "$region"
			response=$?
	done
	#########################################
	echo "[***] Snapshot created"
	sleep 5
}
#########################################

function CreateEncryptedCopy {
	echo "Name: $name"
	echo "Snapshot-ID: $snapshotId"
	#########################################
	echo "[***] Creating Snapshot Copy of encypted format"
	copyName="ENC-$name"
	#########################################
	image_response=$(aws ec2 copy-snapshot \
	  --no-dry-run \
	  --source-snapshot-id "$snapshotId" \
	  --source-region "$region" \
	  --region "$region" \
	  --description "Encrypted Copy of $name" \
	  --encrypted )
	#########################################
	imageId=$(echo -e "$image_response" | /usr/bin/jq '.SnapshotId' | tr -d '"')
	#########################################
	response=1
	while [  "$response" -ne 0 ]; do
			echo "Waiting for Encrypted Snapshot $imageId to become available...."
			aws ec2 wait snapshot-completed --snapshot-id "$imageId" --region "$region"
			response=$?
	done
}

function AddTagToSnapshot {
	echo "[***] Encrypted snapshot $imageId is now ready for use"
	#########################################
	aws ec2 create-tags \
	  --resources "$imageId" \
	  --tags 'Key=Name,Value="$copyName"'
	  --region "$region"
	#########################################
	sleep 5
}


function CreateVolumeFromSnapshot {
	echo "[***] Create volume from encrypted snapshot"
	newvolume_response=$(aws ec2 create volume \
	  --region "$region"
	  --snapshot-id "$imageId"
	  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value="$copyName"}]')
	#########################################
	newvolumeId=$(echo -e "$newvolume_response" | /usr/bin/jq '.VolumeId' | tr -d '"')
	#########################################
	response=1
	while [  "$response" -ne 0 ]; do
			echo "Waiting for Encrypted Snapshot $imageId to become available...."
			aws ec2 wait volume-available --volume-ids "$newvolumeId" --region "$region"
			response=$?
	done
	echo "[***] The volume $newvolumeId is now ready for use"
}

function CheckCurrentStateOfInstance {
	echo "[***] Check if the instance is in running state"
	current_response=$(aws ec2 describe-instances --filters Name=instance-id,Values="$instanceId" --region "$region")
	#echo $current_response
	status_of_instance=$(echo -e "$current_response" | /usr/bin/jq '.Reservations[].Instances[].State.Code' | tr -d '"')
	echo $status_of_instance
	if [ "$status_of_instance" -eq 64 ]; then
		echo "[***] Instance is stopping"
	elif [ "$status_of_instance" -eq 16 ]; then
		echo "[***] Instance is running"
	elif [ "$status_of_instance" -eq 80 ]; then
		echo "[***] Instance is stopped"		
	fi
	return $status_of_instance
}

function StopInstance {
	echo "[***] Stop Instance"
	stop_response=$(aws ec2 stop-instances --instance-ids "$instanceId" --region "$region")
	echo $stop_response
	current_state=$(CheckCurrentStateOfInstance)
	while [ "$current_state" -ne 80 ]; do
			current_state=$(CheckCurrentStateOfInstance)
			sleep 15
	done
	echo "[***] Instance is now stopped"
}

function DetachOldVolumeToInstance {
	echo "[***] Detach old volume from the Instance"
	detach_response=$(aws ec2 detach-volume --volume-id "$volume_data" --region "$region")
	echo "[***] Waiting for the volume to detach"
	sleep 10
	vol_becomes_available=$(aws ec2 describe-volumes --volume-id "$volume_data" --region "$region")
	vol_state=$(echo -e "$vol_becomes_available" | /usr/bin/jq '.Volumes[].State' | tr -d '"')
	if [ $vol_state -eq "available" ]
	then
		echo "[***] Old Volume is now detached"
	fi
}

function AttachNewVolumeToInstance {
	echo "[***] Attach new volume to the Instance"
	attach_response=$(aws ec2 attach-volume --volume-id $newvolumeId --instance-id $instanceId --device $attachment_details)
	new_vol_becomes_available=$(aws ec2 describe-volumes --volume-id "$newvolumeId" --region "$region")
	vol_state=$(echo -e "$new_vol_becomes_available" | /usr/bin/jq '.Volumes[].State' | tr -d '"')
	if [ $vol_state -eq "in-use" ]
	then
		echo "[***] Old Volume is now detached"
	fi
}

function StartInstance {
	echo "[***] Start Instance"
	start_response=$(aws ec2 start-instances --instance-ids "$instanceId" --region "$region")
	current_state=$(CheckCurrentStateOfInstance)
	while [ "$current_state" -eq 16 ]; do
			current_state=$(CheckCurrentStateOfInstance)
			sleep 15
	done
	echo "[***] Instance is now running"
}

main() {
	AllChecksDone
	GetEC2VolumeDetails	
	CreateSnapshotFromVolume
	CreateEncryptedCopy
	AddTagToSnapshot
	CreateVolumeFromSnapshot
	CheckCurrentStateOfInstance
	StopInstance
	DetachOldVolumeToInstance
	AttachNewVolumeToInstance
	StartInstance
}

main "$@"
