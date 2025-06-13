#!/bin/sh
set -eu

version_file="${GROCY_DATAPATH}/.container-grocy-version"

if [ -f "${version_file}" ]; then
	old_grocy_version=$(cat "${version_file}")
	case $(apk version -t "${GROCY_VERSION}" "${old_grocy_version}") in
	"<")
		echo "Downgrades are not supported!"
		exit 1
		;;
	">")
		# Clear the viewcache directory
		[ -d "${viewcache_path:=${GROCY_DATAPATH}/viewcache}" ] && find "${viewcache_path}" -mindepth 1 -delete
		# Perform a DB backup
		if [ -f "${db_file:=${GROCY_DATAPATH}/grocy.db}" ]; then
			mkdir -p "${backup_path:=${GROCY_DATAPATH}/backups}"
			php <<-EOT
				<?php
				\$db = new SQLite3('${db_file}', SQLITE3_OPEN_READONLY);
				\$db->enableExceptions(true);
				\$db->exec( "VACUUM INTO '${backup_path}/grocy-${old_grocy_version}_pre-${GROCY_VERSION}.db';" );
				\$db->close();
			EOT
			# Delete old DB backups except from the previous version.
			find "${backup_path}" -maxdepth 1 -type f -name 'grocy-*_pre-*.db' -and -not -name "*${old_grocy_version}*" -delete
		fi
		;;
	esac
fi

# Persist the current grocy version
printf '%s' "${GROCY_VERSION}" >"${version_file}"

# Initialize the data volume but do not overwrite existing files
cp -anv -t "${GROCY_DATAPATH}" /var/www/data/*

# Invoke grocy to generate or update the grocy.db
# Ensure the www-data user has proper access (php-fpm drops to `www-data` when started as root user)
if [ "$(id -u)" = "0" ]; then
	chown --changes --recursive "www-data:www-data" "${GROCY_DATAPATH}"
	su -s "$(which php)" www-data /var/www/public/index.php # create new hash file
	su -s "$(which php)" www-data /var/www/public/index.php # do the migration
else
	php -f /var/www/public/index.php # create new hash file
	php -f /var/www/public/index.php # do the migration
fi

# Run to the supplied CMD
exec "$@"
