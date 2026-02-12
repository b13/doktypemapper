#!/usr/bin/env bash

#
# doktypemapper test runner.
#
# Executes test suites using direct docker/podman container commands
# with ghcr.io/typo3/core-testing-* images.
#

cleanUp() {
    ATTACHED_CONTAINERS=$(${CONTAINER_BIN} ps --filter network=${NETWORK} --format='{{.Names}}' 2>/dev/null)
    for ATTACHED_CONTAINER in ${ATTACHED_CONTAINERS}; do
        ${CONTAINER_BIN} kill ${ATTACHED_CONTAINER} >/dev/null 2>&1
    done
    ${CONTAINER_BIN} network rm ${NETWORK} >/dev/null 2>&1
}

waitFor() {
    local HOST=${1}
    local PORT=${2}
    local TESTCOMMAND="
        COUNT=0;
        while ! nc -z ${HOST} ${PORT} 2>/dev/null; do
            if [ \"\${COUNT}\" -gt 20 ]; then
                echo \"Can not connect to ${HOST} port ${PORT}. Aborting.\";
                exit 1;
            fi;
            sleep 1;
            COUNT=\$((COUNT + 1));
        done;
    "
    ${CONTAINER_BIN} run ${CONTAINER_COMMON_PARAMS} --network ${NETWORK} --name wait-for-${SUFFIX} ${IMAGE_PHP} /bin/sh -c "${TESTCOMMAND}"
    if [ $? -gt 0 ]; then
        kill -SIGTERM "${BASH_PID}" 2>/dev/null
    fi
}

loadHelp() {
    read -r -d '' HELP <<EOF
doktypemapper test runner. Execute unit, functional test suites and more.

Usage: $0 [options] [file]

Options:
    -s <...>
        Specifies which test suite to run
            - cgl: PHP coding guidelines check
            - composerInstall: "composer install"
            - composerValidate: "composer validate"
            - functional: functional tests
            - lint: PHP linting
            - phpstan: PHPStan static analysis
            - unit (default): PHP unit tests
            - update: pull latest container images

    -b <docker|podman>
        Container binary to use (default: docker)

    -t <11|12|13|14>
        TYPO3 core major version for testing.
            - 12 (default)

    -d <mariadb|postgres|sqlite>
        Only with -s functional
        Specifies on which DBMS tests are performed
            - mariadb (default): use MariaDB
            - postgres: use PostgreSQL
            - sqlite: use SQLite

    -p <7.4|8.0|8.1|8.2|8.3|8.4>
        Specifies the PHP minor version to be used
            - 8.1 (default)

    -e "<phpunit options>"
        Only with -s functional|unit
        Additional options to send to phpunit.
        Example -e "-v --filter canRetrieveValueWithGP"

    -x
        Only with -s functional|unit
        Send information to host instance for xdebug break points.

    -y <port>
        Send xdebug information to a different port than default 9003.

    -n
        Only with -s cgl
        Activate dry-run in CGL check that does not actively change files.

    -u
        Update existing container images.

    -v
        Enable verbose script output. Shows variables and docker commands.

    -h
        Show this help.

Examples:
    # Run unit tests using PHP 8.1
    ./Build/Scripts/runTests.sh

    # Run unit tests using PHP 8.4
    ./Build/Scripts/runTests.sh -p 8.4

    # Run functional tests with MariaDB
    ./Build/Scripts/runTests.sh -s functional

    # Install composer dependencies for TYPO3 14
    ./Build/Scripts/runTests.sh -s composerInstall -t 14 -p 8.4
EOF
}

# Go to the directory this script is located, so everything else is relative
# to this dir, no matter from where this script is called.
THIS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "${THIS_SCRIPT_DIR}" || exit 1

# Go to extension root
cd ../../ || exit 1
ROOT_DIR=$(pwd)

# Option defaults
TEST_SUITE="unit"
DBMS="mariadb"
PHP_VERSION="8.1"
PHP_XDEBUG_ON=0
PHP_XDEBUG_PORT=9003
EXTRA_TEST_OPTIONS=""
SCRIPT_VERBOSE=0
CGLCHECK_DRY_RUN=""
TYPO3="12"
CONTAINER_BIN="docker"

# Option parsing
OPTIND=1
INVALID_OPTIONS=()
while getopts ":s:b:d:p:e:t:xy:nhuv" OPT; do
    case ${OPT} in
        s)
            TEST_SUITE=${OPTARG}
            ;;
        b)
            CONTAINER_BIN=${OPTARG}
            ;;
        d)
            DBMS=${OPTARG}
            ;;
        p)
            PHP_VERSION=${OPTARG}
            ;;
        t)
            TYPO3=${OPTARG}
            ;;
        e)
            EXTRA_TEST_OPTIONS=${OPTARG}
            ;;
        x)
            PHP_XDEBUG_ON=1
            ;;
        y)
            PHP_XDEBUG_PORT=${OPTARG}
            ;;
        h)
            loadHelp
            echo "${HELP}"
            exit 0
            ;;
        n)
            CGLCHECK_DRY_RUN="-n"
            ;;
        u)
            TEST_SUITE=update
            ;;
        v)
            SCRIPT_VERBOSE=1
            ;;
        \?)
            INVALID_OPTIONS+=(${OPTARG})
            ;;
        :)
            INVALID_OPTIONS+=(${OPTARG})
            ;;
    esac
done

# Exit on invalid options
if [ ${#INVALID_OPTIONS[@]} -ne 0 ]; then
    echo "Invalid option(s):" >&2
    for I in "${INVALID_OPTIONS[@]}"; do
        echo "-${I}" >&2
    done
    echo >&2
    loadHelp
    echo "${HELP}" >&2
    exit 1
fi

# Set $1 to first mass argument, this is the optional test file or test directory to execute
shift $((OPTIND - 1))
TEST_FILE=${1}

if [ ${SCRIPT_VERBOSE} -eq 1 ]; then
    set -x
fi

# Container setup
PHP_MINOR="${PHP_VERSION/./}"
IMAGE_PHP="ghcr.io/typo3/core-testing-php${PHP_MINOR}:latest"
SUFFIX=$(echo $RANDOM)
NETWORK="doktypemapper-${SUFFIX}"

${CONTAINER_BIN} network create ${NETWORK} >/dev/null 2>&1

BASH_PID=$$

CONTAINER_COMMON_PARAMS="--rm --network ${NETWORK} --user $(id -u):$(id -g) -v ${ROOT_DIR}:${ROOT_DIR} -w ${ROOT_DIR}"

if [ ${PHP_XDEBUG_ON} -eq 0 ]; then
    XDEBUG_MODE="-e XDEBUG_MODE=off"
    XDEBUG_CONFIG=""
else
    HOST_OS_IP=$(${CONTAINER_BIN} run --rm --network ${NETWORK} alpine ip route | awk '/default/ { print $3 }')
    XDEBUG_MODE="-e XDEBUG_MODE=debug,develop"
    XDEBUG_CONFIG="-e XDEBUG_CONFIG=\"client_port=${PHP_XDEBUG_PORT} client_host=${HOST_OS_IP}\""
fi

# Suite execution
case ${TEST_SUITE} in
    cgl)
        if [ -n "${CGLCHECK_DRY_RUN}" ]; then
            CGLCHECK_DRY_RUN="--dry-run --diff"
        fi
        COMMAND="php -dxdebug.mode=off .Build/vendor/friendsofphp/php-cs-fixer/php-cs-fixer fix -v ${CGLCHECK_DRY_RUN} --config=Build/php-cs-fixer.php --using-cache=no"
        ${CONTAINER_BIN} run ${CONTAINER_COMMON_PARAMS} ${XDEBUG_MODE} --name cgl-${SUFFIX} ${IMAGE_PHP} /bin/sh -c "${COMMAND}"
        SUITE_EXIT_CODE=$?
        ;;
    composerInstall)
        COMMAND="php -v | grep '^PHP'; "
        if [ "${TYPO3}" -eq 11 ]; then
            COMMAND+="composer require typo3/cms-backend:^11.5 --dev -W --no-progress --no-interaction"
        elif [ "${TYPO3}" -eq 12 ]; then
            COMMAND+="composer require typo3/cms-backend:^12.4 --dev -W --no-progress --no-interaction"
        elif [ "${TYPO3}" -eq 13 ]; then
            COMMAND+="composer require typo3/cms-backend:^13.4 --dev -W --no-progress --no-interaction"
        elif [ "${TYPO3}" -eq 14 ]; then
            COMMAND+="composer require typo3/cms-backend:^14.0 --dev -W --no-progress --no-interaction"
        else
            COMMAND+="composer install --dev --no-progress --no-interaction"
        fi
        ${CONTAINER_BIN} run ${CONTAINER_COMMON_PARAMS} -v ${HOME}:${HOME} ${XDEBUG_MODE} --name composer-install-${SUFFIX} ${IMAGE_PHP} /bin/sh -c "${COMMAND}"
        SUITE_EXIT_CODE=$?
        ;;
    composerValidate)
        COMMAND="php -v | grep '^PHP'; composer validate"
        ${CONTAINER_BIN} run ${CONTAINER_COMMON_PARAMS} -v ${HOME}:${HOME} ${XDEBUG_MODE} --name composer-validate-${SUFFIX} ${IMAGE_PHP} /bin/sh -c "${COMMAND}"
        SUITE_EXIT_CODE=$?
        ;;
    functional)
        case ${DBMS} in
            mariadb)
                ${CONTAINER_BIN} run --rm --network ${NETWORK} --name mariadb-${SUFFIX} \
                    -e MYSQL_ROOT_PASSWORD=funcp \
                    --tmpfs /var/lib/mysql/:rw,noexec,nosuid \
                    -d mariadb:10
                waitFor mariadb-${SUFFIX} 3306
                CONTAINERPARAMS="-e typo3DatabaseName=func_test -e typo3DatabaseUsername=root -e typo3DatabasePassword=funcp -e typo3DatabaseHost=mariadb-${SUFFIX}"
                ${CONTAINER_BIN} run ${CONTAINER_COMMON_PARAMS} ${CONTAINERPARAMS} ${XDEBUG_MODE} ${XDEBUG_CONFIG} \
                    -v ${HOME}:${HOME} --name functional-mariadb-${SUFFIX} ${IMAGE_PHP} \
                    /bin/sh -c "php -v | grep '^PHP'; .Build/bin/phpunit -c Build/phpunit/FunctionalTests.xml ${EXTRA_TEST_OPTIONS} ${TEST_FILE}"
                SUITE_EXIT_CODE=$?
                ;;
            postgres)
                ${CONTAINER_BIN} run --rm --network ${NETWORK} --name postgres-${SUFFIX} \
                    -e POSTGRES_PASSWORD=funcp \
                    -e POSTGRES_USER=$(id -un) \
                    --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid \
                    -d postgres:10
                waitFor postgres-${SUFFIX} 5432
                CONTAINERPARAMS="-e typo3DatabaseDriver=pdo_pgsql -e typo3DatabaseName=func_test -e typo3DatabaseUsername=$(id -un) -e typo3DatabasePassword=funcp -e typo3DatabaseHost=postgres-${SUFFIX}"
                ${CONTAINER_BIN} run ${CONTAINER_COMMON_PARAMS} ${CONTAINERPARAMS} ${XDEBUG_MODE} ${XDEBUG_CONFIG} \
                    -v ${HOME}:${HOME} --name functional-postgres-${SUFFIX} ${IMAGE_PHP} \
                    /bin/sh -c "php -v | grep '^PHP'; .Build/bin/phpunit -c Build/phpunit/FunctionalTests.xml ${EXTRA_TEST_OPTIONS} ${TEST_FILE}"
                SUITE_EXIT_CODE=$?
                ;;
            sqlite)
                ${CONTAINER_BIN} run ${CONTAINER_COMMON_PARAMS} ${XDEBUG_MODE} ${XDEBUG_CONFIG} \
                    -v ${HOME}:${HOME} \
                    -e typo3DatabaseDriver=pdo_sqlite \
                    --name functional-sqlite-${SUFFIX} ${IMAGE_PHP} \
                    /bin/sh -c "php -v | grep '^PHP'; .Build/bin/phpunit -c Build/phpunit/FunctionalTests.xml ${EXTRA_TEST_OPTIONS} ${TEST_FILE}"
                SUITE_EXIT_CODE=$?
                ;;
            *)
                echo "Invalid -d option argument ${DBMS}" >&2
                echo >&2
                loadHelp
                echo "${HELP}" >&2
                exit 1
        esac
        ;;
    lint)
        COMMAND="php -v | grep '^PHP'; find . -name \\*.php ! -path './.Build/*' -print0 | xargs -0 -n1 -P4 php -dxdebug.mode=off -l >/dev/null"
        ${CONTAINER_BIN} run ${CONTAINER_COMMON_PARAMS} ${XDEBUG_MODE} --name lint-${SUFFIX} ${IMAGE_PHP} /bin/sh -c "${COMMAND}"
        SUITE_EXIT_CODE=$?
        ;;
    phpstan)
        COMMAND="php -v | grep '^PHP'; php -dxdebug.mode=off .Build/bin/phpstan analyze -c Build/phpstan.neon --no-progress --no-interaction"
        ${CONTAINER_BIN} run ${CONTAINER_COMMON_PARAMS} -v ${HOME}:${HOME} ${XDEBUG_MODE} --name phpstan-${SUFFIX} ${IMAGE_PHP} /bin/sh -c "${COMMAND}"
        SUITE_EXIT_CODE=$?
        ;;
    unit)
        COMMAND="php -v | grep '^PHP'; .Build/bin/phpunit -c Build/phpunit/UnitTests.xml ${EXTRA_TEST_OPTIONS} ${TEST_FILE}"
        ${CONTAINER_BIN} run ${CONTAINER_COMMON_PARAMS} -v ${HOME}:${HOME} ${XDEBUG_MODE} ${XDEBUG_CONFIG} --name unit-${SUFFIX} ${IMAGE_PHP} /bin/sh -c "${COMMAND}"
        SUITE_EXIT_CODE=$?
        ;;
    update)
        # Pull ghcr.io/typo3/core-testing-* images
        ${CONTAINER_BIN} images ghcr.io/typo3/core-testing-*:latest --format "{{.Repository}}:latest" | xargs -I {} ${CONTAINER_BIN} pull {}
        # Remove dangling images
        ${CONTAINER_BIN} images ghcr.io/typo3/core-testing-* --filter "dangling=true" --format "{{.ID}}" | xargs -I {} ${CONTAINER_BIN} rmi {}
        ;;
    *)
        echo "Invalid -s option argument ${TEST_SUITE}" >&2
        echo >&2
        loadHelp
        echo "${HELP}" >&2
        exit 1
esac

cleanUp

exit $SUITE_EXIT_CODE
