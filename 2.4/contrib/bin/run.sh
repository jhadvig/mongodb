#!/bin/bash

# SCL in CentOS/RHEL 7 doesn't support --exec, we need to do it ourselves
source scl_source enable mongodb24
set -e

function usage {
	echo "You must specify following environment variables:"
	echo "  \$MONGODB_USER"
	echo "  \$MONGODB_PASSWORD"
	echo "  \$MONGODB_DB - optional (default database - 'production')"
	echo "  \$MONGODB_ADMIN_PASSWORD - optional"
	exit 1
}

function create_mongodb_users {
	mongod -f /opt/openshift/etc/mongodb.conf &

	# Check if the MongoDB daemon is up.
	RC=1
	while [[ RC -ne 0 ]]; do
	    echo "=> Waiting for confirmation of MongoDB service startup"
	    sleep 2
	    set +e
	    mongo admin --eval "help" >/dev/null 2>&1
	    RC=$?
	    set -e
	done

	# Make sure env variables don't propagate to mongod process.
	mongo_user="$MONGODB_USER" ; unset MONGODB_USER
	mongo_pass="$MONGODB_PASSWORD" ; unset MONGODB_PASSWORD
	mongo_db=${MONGODB_DATABASE:-"production"} ; unset MONGODB_DATABASE

	# Create MongoDB database admin, if his password is specified with MONGODB_ADMIN_PASSWORD
	if [ "$MONGODB_ADMIN_PASSWORD" ]; then
		echo "=> Creating an admin user with a ${MONGODB_ADMIN_PASSWORD} password in MongoDB"
		mongo admin --eval "db.addUser({user: 'admin', pwd: '$MONGODB_ADMIN_PASSWORD', roles: [ 'dbAdminAnyDatabase', 'userAdminAnyDatabase' , 'readWriteAnyDatabase' ]});"
		unset MONGODB_ADMIN_PASSWORD
	fi

	# Create standard user with read/write permissions, in specified database ('production' by default).
	mongo $mongo_db --eval "db.addUser({user: '${mongo_user}', pwd: '${mongo_pass}', roles: [ 'readWrite' ]});"
	mongo admin --eval "db.shutdownServer();"

	# Create a empty file which indicates that the database users were created.
	touch /var/lib/mongodb/.mongodb_users_created

	# Check if the MongoDB daemon is down.
	while [[ RC -eq 0 ]]
		sleep 2
		set +e
		mongo admin --eval "help" >/dev/null 2>&1
		RC=$?
		set -e
	done
}

test -z "$MONGODB_USER" && usage
test -z "$MONGODB_PASSWORD" && usage

if [ ! -f /var/lib/mongodb/.mongodb_users_created ]; then
	create_mongodb_users
fi

exec mongod -f /opt/openshift/etc/mongodb.conf --auth
