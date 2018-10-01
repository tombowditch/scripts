#!/bin/bash
# Backup script to Google Cloud Storage
# Requires gsutil (https://cloud.google.com/storage/docs/gsutil) to be initialized 


# CONFIG #

# Set your backup locations here (folders)

backup_locations=('/var/www' '/etc')
google_bucket="backups"

# END CONFIG #

if ! [ -x "$(command -v gsutil)" ]; then
  echo 'Error: gsutil is not installed.' >&2
  exit 1
fi

function run_backup {
  gsutil -m rsync -e -r $1 gs://$google_bucket$1
}

function backup {
  echo "Running backup: $1 | $(date)"
  run_backup $1
  echo "Backup ran: $1"
}

for loc in "${backup_locations[@]}"
do
	backup $loc
done

echo "Backup completed successfully at $(date)"
