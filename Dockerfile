# syntax=docker.io/docker/dockerfile:1
# check=error=true

# Supported grocy and php version
ARG GROCY_VERSION=4.5.0
ARG BASE_IMAGE=docker.io/php:8.3-fpm-alpine

# Build environment and defaults
ARG GROCY_DATAPATH=/data
ARG COMPOSER_ALLOW_SUPERUSER=1
ARG COMPOSER_HOME=/var/local/cache/grocy-${GROCY_VERSION}/${TARGETARCH}${TARGETVARIANT}/composer
ARG YARN_CACHE_FOLDER=/var/local/cache/grocy-${GROCY_VERSION}/${TARGETARCH}${TARGETVARIANT}/yarn

# Collect all source files and cache as layer
FROM scratch AS source
ADD --link --chmod=755 src/entrypoint.sh /

## php extension installer
ADD --link --checksum=sha256:061b5542e57ccf07e6fcffe9f72627287731313889611a94bd838b53cabba8fc --chmod=755 https://github.com/mlocati/docker-php-extension-installer/releases/download/2.9.18/install-php-extensions /

## NGINX (the index.xml is used to invalidate the build cache, when a new NGINX revision is released)
ADD --link --checksum=sha256:ff7cf138acc09f2a5029300ab713fe6a1440605fca72e2bab76a4da9206fec87 --chmod=644 https://nginx.org/keys/nginx_signing.rsa.pub /nginx/
ADD --link --chmod=644 https://nginx.org/packages/mainline/index.xml /nginx/
ADD --link --chmod=644 src/nginx.conf /nginx/

## Pull Grocy from upstream and create a stub for the config.php
ARG GROCY_VERSION
ADD --link --keep-git-dir=true https://github.com/grocy/grocy.git#v${GROCY_VERSION} /grocy
ADD --link --checksum=sha256:efa691e650a31339209feca571799058e0ce89a6c60531dd204a20b2129f8dbc --chmod=644 https://berrnd.de/data/Bernd_Bestel.asc /grocy/
ADD --link --chmod=644 src/config.php /grocy/data/

# Prepare base image
FROM ${BASE_IMAGE} AS php-fpm
RUN --mount=type=bind,from=source,source=/install-php-extensions,target=/usr/local/bin/install-php-extensions \
	sh -eux -o pipefail <<-'EOT'
	# Use default settings for php in production
	mv "${PHP_INI_DIR}/php.ini-production" "${PHP_INI_DIR}/php.ini"

	# Install additional grocy dependencies and enable opcode caching (JIT support requires a defined buffer size)
	install-php-extensions gd intl ldap
	docker-php-ext-enable opcache
	echo 'opcache.jit_buffer_size=256M' >"${PHP_INI_DIR}/conf.d/zzz-grocy.ini"

	# Override the php-fpm [www] pool for grocy to listen on a unix socket
	cat <<-'EOF' >"${PHP_INI_DIR}/../php-fpm.d/zzz-grocy.conf"
		[www]
		listen = /tmp/php-fpm.sock
		listen.mode = 0666 ; Using a user/group would prevent the container from being executed as an unknown non-root user.
		access.log = /dev/null ; Logging can be done in the reverse proxy as needed.
	EOF

	php-fpm --test
EOT

# Build Grocy under /rootfs/var/www
FROM php-fpm AS builder
RUN --mount=type=bind,from=source,source=/install-php-extensions,target=/usr/local/bin/install-php-extensions \
	install-php-extensions @composer
RUN apk add --no-cache git gnupg yarn
ARG GROCY_VERSION
ARG COMPOSER_ALLOW_SUPERUSER COMPOSER_HOME YARN_CACHE_FOLDER
WORKDIR /rootfs/var/www
RUN --mount=type=bind,from=source,source=/grocy,target=/grocy \
	--mount=type=cache,target=${COMPOSER_HOME}/cache \
	--mount=type=cache,target=${YARN_CACHE_FOLDER} \
	--mount=type=tmpfs,target=/tmp \
	sh -eux -o pipefail <<-EOT
	gpg --batch --import /grocy/Bernd_Bestel.asc
	git -C /grocy verify-commit v${GROCY_VERSION}
	git -C /grocy archive --prefix=data/ --add-file=data/config.php --prefix= v${GROCY_VERSION} | tar xf -

	composer install --no-interaction --no-dev --optimize-autoloader
	yarn install
EOT

## Test the prerequisites to fail if something is wrong (or has changed).
RUN php <<-EOT
	<?php
	define("GROCY_DATAPATH", "/rootfs/var/www/data");
	require_once("helpers/PrerequisiteChecker.php"); 
	(new PrerequisiteChecker())->checkRequirements();
EOT

## Import the entrypoint.sh used to manage the /data volume
COPY --link --from=source /entrypoint.sh /rootfs/entrypoint.sh

# Use NGINX as webserver and multirun to run PHP-FPM and NGINX in combination
FROM php-fpm AS webserver
RUN --mount=type=bind,from=source,source=/nginx,target=/nginx \
	--mount=type=tmpfs,target=/tmp \
	sh -eux -o pipefail <<-EOT
	echo "@nginx-repo https://nginx.org/packages/mainline/alpine/v$(egrep -o '^[0-9]+\.[0-9]+' /etc/alpine-release)/main" >> /etc/apk/repositories
	cp -a /nginx/nginx_signing.rsa.pub /etc/apk/keys/nginx_signing.rsa.pub
	apk add --no-cache nginx@nginx-repo multirun
	chmod o+x /usr/bin/multirun
	nginx -V

	# Validate the nginx.conf for php-fpm
	cp -a /nginx/nginx.conf /etc/nginx/nginx.conf
	nginx -t -c /etc/nginx/nginx.conf
EOT
## multirun does not handle SIGQUIT
STOPSIGNAL SIGINT
EXPOSE 8080
ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "multirun", "php-fpm","nginx -e stderr -c /etc/nginx/nginx.conf" ]

# Setup the runtime
FROM webserver AS runtime
ARG BASE_IMAGE GROCY_VERSION GROCY_DATAPATH
ENV GROCY_VERSION=${GROCY_VERSION} GROCY_DATAPATH=${GROCY_DATAPATH}
COPY --link --from=builder /rootfs/ /
VOLUME ${GROCY_DATAPATH}

LABEL\
	org.opencontainers.image.title='Grocy' \
	org.opencontainers.image.description='Grocy is a self-hosted groceries & household management solution.' \
	org.opencontainers.image.licenses='MIT' \
	org.opencontainers.image.vendor='Grocy Community (unofficial)' \
	org.opencontainers.image.version="${GROCY_VERSION}" \
	org.opencontainers.image.source='https://github.com/bbx0/container-grocy' \
	org.opencontainers.image.authors='Philipp Micheel <bbx0+grocy@bitdevs.de>' \
	org.opencontainers.image.base.name="${BASE_IMAGE}"
