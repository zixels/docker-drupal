#!/usr/bin/env bash

set -e

if [[ -n "${DEBUG}" ]]; then
    set -x
fi

check_rq() {
    echo "Checking requirement: ${1} must be ${2}"
    drush rq --format=json | jq ".\"${1}\".value" | grep -q "${2}"
    echo "OK"
}

check_status() {
    echo "Checking status: ${1} must be ${2}"
    drush status --format=yaml | grep -q "${1}: ${2}"
    echo "OK"
}

DB_NAME=drupal
DB_HOST=mariadb
DB_USER=drupal
DB_PASS=drupal
DB_URL="mysql://${DB_USER}:${DB_PASS}@${DB_HOST}/${DB_NAME}"

make init -f /usr/local/bin/actions.mk

composer require \
    drupal/redis \
    drupal/search_api \
    drupal/search_api_solr \
    drupal/varnish \
    drupal/features

cd ./web

drush si --db-url="${DB_URL}" -y

# Test Drupal status and requirements
check_status "drush-version" "8.*"
check_status "root" "${APP_ROOT}/${DOCROOT_SUBDIR}"
check_status "drupal-settings-file" "sites/default/settings.php"
check_status "site" "sites/default"
check_status "files" "sites/default/files"
check_status "temp" "/tmp"

check_rq "database_system" "MySQL, MariaDB, or equivalent"
check_rq "image_gd" "bundled (2.1.0 compatible)"
check_rq "php" "${PHP_VERSION}"
check_rq "file system" "Writable (<em>public</em> download method)"

drush en -y redis search_api search_api_solr varnish features

# Enable redis
chmod 755 "${PWD}/sites/default/settings.php"
echo "include '${PWD}/sites/default/test.settings.php';" >> "${PWD}/sites/default/settings.php"
drush cc all
check_rq "redis" "Connected, using the <em>PhpRedis</em> client"

# Test solr server connection
drush en -y feature_search_api_solr
check_rq "search_api_solr" "1 server"

# Test varnish cache and purge
curl -Is varnish:6081 | grep -q "X-Varnish-Cache: MISS"
curl -Is varnish:6081 | grep -q "X-Varnish-Cache: HIT"

drush varnish-purge-all

curl -Is varnish:6081 | grep -q "X-Varnish-Cache: MISS"
curl -Is varnish:6081 | grep -q "X-Varnish-Cache: HIT"
