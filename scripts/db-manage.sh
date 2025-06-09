#!/bin/bash

# Database Management Script for SaaS Factory
# Usage: ./scripts/db-manage.sh [command] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/core/database/docker-compose.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if PostgreSQL container is running
check_postgres() {
    if ! docker ps | grep -q "saas-factory-postgres"; then
        log_error "PostgreSQL container is not running"
        log_info "Start it with: cd core/database && docker-compose up -d"
        exit 1
    fi
}

# Load environment variables
load_env() {
    if [ -f "$PROJECT_ROOT/.env" ]; then
        export $(cat "$PROJECT_ROOT/.env" | grep -v '^#' | xargs)
    else
        log_error ".env file not found in project root"
        exit 1
    fi
}

# Create a new database and user
create_database() {
    local db_name="$1"
    
    if [ -z "$db_name" ]; then
        log_error "Database name is required"
        echo "Usage: $0 create <database_name>"
        exit 1
    fi
    
    # Validate database name (alphanumeric + underscores only)
    if ! [[ "$db_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        log_error "Invalid database name. Use only alphanumeric characters and underscores, starting with a letter."
        exit 1
    fi
    
    log_info "Creating database '$db_name'..."
    
    local user_name="${db_name}_user"
    local password="${db_name}_pass_$(openssl rand -hex 8)"
    
    # Check if database already exists
    if docker exec saas-factory-postgres psql -U postgres -lqt | cut -d \| -f 1 | grep -qw "$db_name"; then
        log_warning "Database '$db_name' already exists"
        return 0
    fi
    
    # Create database and user (separate commands to avoid transaction issues)
    docker exec saas-factory-postgres psql -U postgres -c "CREATE DATABASE $db_name;"
    docker exec saas-factory-postgres psql -U postgres -c "CREATE USER $user_name WITH ENCRYPTED PASSWORD '$password';"
    docker exec saas-factory-postgres psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE $db_name TO $user_name;"
    
    # Grant schema privileges
    docker exec saas-factory-postgres psql -U postgres -d "$db_name" -c "GRANT ALL ON SCHEMA public TO $user_name;"
    docker exec saas-factory-postgres psql -U postgres -d "$db_name" -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $user_name;"
    docker exec saas-factory-postgres psql -U postgres -d "$db_name" -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $user_name;"
    docker exec saas-factory-postgres psql -U postgres -d "$db_name" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $user_name;"
    docker exec saas-factory-postgres psql -U postgres -d "$db_name" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $user_name;"
    
    log_success "Database '$db_name' created successfully"
    echo ""
    echo "📋 Database Details:"
    echo "   Database: $db_name"
    echo "   User: $user_name"
    echo "   Password: $password"
    echo "   Connection URL: postgresql://$user_name:$password@postgres:5432/$db_name"
    echo ""
    echo "💾 Save these credentials securely!"
}

# List all databases
list_databases() {
    log_info "Listing all databases..."
    
    echo ""
    echo "📊 PostgreSQL Databases:"
    echo "========================"
    docker exec saas-factory-postgres psql -U postgres -c "
        SELECT 
            datname as \"Database\",
            pg_size_pretty(pg_database_size(datname)) as \"Size\",
            datcollate as \"Collation\"
        FROM pg_database 
        WHERE datistemplate = false
        ORDER BY datname;
    "
    
    echo ""
    echo "👥 Database Users:"
    echo "=================="
    docker exec saas-factory-postgres psql -U postgres -c "
        SELECT 
            usename as \"Username\",
            usesuper as \"Superuser\",
            usecreatedb as \"Create DB\"
        FROM pg_user 
        WHERE usename != 'postgres'
        ORDER BY usename;
    "
}

# Backup database
backup_database() {
    local db_name="$1"
    local backup_dir="$PROJECT_ROOT/backups"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    
    if [ -z "$db_name" ]; then
        log_error "Database name is required"
        echo "Usage: $0 backup <database_name>"
        exit 1
    fi
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    local backup_file="$backup_dir/${db_name}_${timestamp}.sql"
    
    log_info "Creating backup of database '$db_name'..."
    
    # Create backup
    docker exec saas-factory-postgres pg_dump -U postgres -d "$db_name" > "$backup_file"
    
    # Compress backup
    gzip "$backup_file"
    backup_file="${backup_file}.gz"
    
    log_success "Backup created: $backup_file"
    
    # Show backup size
    local size=$(du -h "$backup_file" | cut -f1)
    echo "   Size: $size"
    
    # Clean old backups (keep last 10)
    log_info "Cleaning old backups (keeping last 10)..."
    find "$backup_dir" -name "${db_name}_*.sql.gz" -type f -printf '%T@ %p\n' | \
        sort -nr | tail -n +11 | cut -d' ' -f2- | xargs -r rm
}

# Restore database
restore_database() {
    local backup_file="$1"
    local db_name="$2"
    
    if [ -z "$backup_file" ] || [ -z "$db_name" ]; then
        log_error "Both backup file and database name are required"
        echo "Usage: $0 restore <backup_file> <database_name>"
        exit 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    log_warning "This will overwrite the existing database '$db_name'"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Restore cancelled"
        exit 0
    fi
    
    log_info "Restoring database '$db_name' from '$backup_file'..."
    
    # Drop existing database (if exists) and recreate
    docker exec saas-factory-postgres psql -U postgres -c "
        SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$db_name';
        DROP DATABASE IF EXISTS $db_name;
        CREATE DATABASE $db_name;
    "
    
    # Restore from backup
    if [[ "$backup_file" == *.gz ]]; then
        zcat "$backup_file" | docker exec -i saas-factory-postgres psql -U postgres -d "$db_name"
    else
        cat "$backup_file" | docker exec -i saas-factory-postgres psql -U postgres -d "$db_name"
    fi
    
    log_success "Database '$db_name' restored successfully"
}

# Backup all databases
backup_all() {
    local backup_dir="$PROJECT_ROOT/backups"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    
    log_info "Creating backup of all databases..."
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Get list of databases (excluding system databases)
    local databases=$(docker exec saas-factory-postgres psql -U postgres -tAc "
        SELECT datname FROM pg_database 
        WHERE datistemplate = false 
        AND datname NOT IN ('postgres')
        ORDER BY datname;
    ")
    
    local backup_file="$backup_dir/all_databases_${timestamp}.sql"
    
    # Create full cluster backup
    docker exec saas-factory-postgres pg_dumpall -U postgres > "$backup_file"
    
    # Compress backup
    gzip "$backup_file"
    backup_file="${backup_file}.gz"
    
    log_success "Full backup created: $backup_file"
    
    # Show backup size
    local size=$(du -h "$backup_file" | cut -f1)
    echo "   Size: $size"
    
    # Also create individual database backups
    echo ""
    log_info "Creating individual database backups..."
    for db in $databases; do
        if [ -n "$db" ]; then
            backup_database "$db"
        fi
    done
}

# Show help
show_help() {
    echo "SaaS Factory Database Management"
    echo "================================"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  create <db_name>              Create a new database with dedicated user"
    echo "  list                          List all databases and users"
    echo "  backup <db_name>              Backup a specific database"
    echo "  backup-all                    Backup all databases"
    echo "  restore <backup_file> <db>    Restore database from backup"
    echo "  help                          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 create myapp               # Create 'myapp' database"
    echo "  $0 backup myapp               # Backup 'myapp' database"
    echo "  $0 backup-all                 # Backup all databases"
    echo "  $0 restore backup.sql.gz myapp  # Restore 'myapp' from backup"
    echo ""
    echo "Backups are stored in: $PROJECT_ROOT/backups/"
}

# Main script logic
main() {
    local command="$1"
    
    case "$command" in
        "create")
            load_env
            check_postgres
            create_database "$2"
            ;;
        "list")
            check_postgres
            list_databases
            ;;
        "backup")
            load_env
            check_postgres
            backup_database "$2"
            ;;
        "backup-all")
            load_env
            check_postgres
            backup_all
            ;;
        "restore")
            load_env
            check_postgres
            restore_database "$2" "$3"
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
