#!/bin/bash

set -e
set -u

# Function to create database and user
create_user_and_database() {
    local database=$1
    local user="${database}_user"
    local password="${database}_pass_$(openssl rand -hex 8)"
    
    echo "Creating database '$database' and user '$user'..."
    
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
        CREATE DATABASE $database;
        CREATE USER $user WITH ENCRYPTED PASSWORD '$password';
        GRANT ALL PRIVILEGES ON DATABASE $database TO $user;
        
        -- Grant schema privileges
        \c $database
        GRANT ALL ON SCHEMA public TO $user;
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $user;
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $user;
        
        -- Grant default privileges for future objects
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $user;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $user;
EOSQL

    echo "Database '$database' and user '$user' created successfully"
    echo "Password for $user: $password"
    echo "Connection string: postgresql://$user:$password@postgres:5432/$database"
    echo "---"
}

# Create databases from POSTGRES_MULTIPLE_DATABASES environment variable
if [ -n "${POSTGRES_MULTIPLE_DATABASES:-}" ]; then
    echo "Creating multiple databases: $POSTGRES_MULTIPLE_DATABASES"
    for db in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
        create_user_and_database $db
    done
else
    echo "No additional databases to create"
fi

echo "Database initialization completed"
