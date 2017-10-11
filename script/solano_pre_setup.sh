#!/bin/bash
# Determine which setup actions need to be performed based 
# on presence/value of calculated cache keys

KEY_DIR_SESSION=$HOME/.session-cache-keys
KEY_DIR_STORED=$HOME/cache-keys
DB_DUMP_FILE=$TDDIUM_REPO_ROOT/tmp/db_dump.sql

set -o errexit -o pipefail # Exit on errors

hash_keys_match() {
  key=$1
  if [ ! -f $KEY_DIR_SESSION/$key ]; then
    echo "NOTICE: No session cache key file for '${key}'"
    return 1
  fi
  if [ ! -f $KEY_DIR_STORED/$key ]; then
    echo "NOTICE: No stored cache key file for '${key}'"
    return 2
  fi
  if [[ "`cat $KEY_DIR_SESSION/$key`" != "`cat $KEY_DIR_STORED/$key`" ]]; then
    echo "NOTICE: Session and stored cache keys for '${key}' do not match"
    return 3
  fi
}

run_setup_task() {
  key=$1
  echo "NOTICE: `date -u '+%Y-%m-%d %H:%M:%S UTC'` - '$key' setup task started"
  time_start=`date +%s`
  case "$key" in
    bundle)
      bundle install --path=$HOME/bundle --no-deployment
      bundle clean # Remove old/extraneous gems
      ;;
    node)
      npm install
      npm prune # Remove old/extraneous node packages
      ;;
    db)
      bundle exec rake db:drop db:create db:schema:load
      mkdir -p $TDDIUM_REPO_ROOT/tmp
      mysqldump -u$TDDIUM_DB_USER -p$TDDIUM_DB_PASSWORD $TDDIUM_DB_NAME > $DB_DUMP_FILE
      ;;
    *)
      echo "ERROR: setup task '$key' is unhandled!"
      exit 4
      ;;
   esac
   time_end=`date +%s`
   echo "NOTICE: `date -u '+%Y-%m-%d %H:%M:%S UTC'` - '$key' setup task completed in $((time_end - time_start)) second[s]"
}

store_cache_key() {
  key=$1
  mkdir -p $KEY_DIR_STORED
  if [ -f $KEY_DIR_SESSION/$key ]; then
    cp -f $KEY_DIR_SESSION/$key $KEY_DIR_STORED/$key
  else
    echo "NOTICE: '$key' does not exist at $KEY_DIR_SESSION/$key"
  fi
}


for key in bundle node db; do
  if ! hash_keys_match $key; then
    run_setup_task $key
  elif [[ "$key" == "db" ]]; then
    # Ensure the database is loaded
    if [ -f $DB_DUMP_FILE ]; then
      echo "NOTICE: '$key' cache keys matched. Loading database from dump file."
      mysql -u$TDDIUM_DB_USER -p$TDDIUM_DB_PASSWORD $TDDIUM_DB_NAME < $DB_DUMP_FILE
    else
      echo "NOTICE: '$key' cache keys matched, but db_dump.sql file not present. Re-loading database"
      run_setup_task db
    fi
  else
    echo "NOTICE: '$key' cache keys matched. Nothing to do."
  fi
  store_cache_key $key
done