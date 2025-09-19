#!/bin/bash

DB_HOST="localhost"
DB_PORT="5433"
DB_USER="postgres"
DB_NAME="test_gis"
DB_PASSWORD="postgres"
SCHEMA_TABLE="public.us_congressional_districts"
SRID=4269
GEOM_COL="geom"
WORKDIR="$HOME/code/Source-US-GIS/archive/congressional_districts"

BASE_URL="https://www2.census.gov/geo/tiger/GENZ2023/shp"
ZIPFILE="cb_2023_us_cd118_500k.zip"

mkdir -p "$WORKDIR"
cd "$WORKDIR" || exit 1

# Download if not exists
if [ ! -f "$WORKDIR/$ZIPFILE" ]; then
  echo "Downloading $ZIPFILE..."
  curl -L -o "$WORKDIR/$ZIPFILE" "$BASE_URL/$ZIPFILE"
else
  echo "$ZIPFILE already exists, skipping download."
fi

# Unzip
echo "Unzipping $ZIPFILE..."
unzip -o "$WORKDIR/$ZIPFILE" -d "$WORKDIR"

# Find .shp file
SHP_FILE=$(find "$WORKDIR" -maxdepth 1 -name "*.shp" | head -n1)
if [ -z "$SHP_FILE" ]; then
  echo "❌ No .shp file found in $WORKDIR"
  exit 1
fi

# Create SQL file
SQL_FILE="$WORKDIR/congressional_districts.sql"
: > "$SQL_FILE"

echo "Preparing SQL for $SHP_FILE..."
# Drop and recreate table (-dD), use COPY for bulk load
shp2pgsql -s $SRID -dD -g $GEOM_COL "$SHP_FILE" "$SCHEMA_TABLE" >> "$SQL_FILE"

# Bulk load into Postgres
echo "Loading data into $SCHEMA_TABLE..."
PGPASSWORD="$DB_PASSWORD" psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f "$SQL_FILE"

# Add spatial index + analyze
echo "Creating spatial index..."
PGPASSWORD="$DB_PASSWORD" psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME <<EOF
CREATE INDEX IF NOT EXISTS idx_cd_geom ON $SCHEMA_TABLE USING gist ($GEOM_COL);
ANALYZE $SCHEMA_TABLE;
EOF

echo "✅ All US congressional districts (118th Congress) imported into $SCHEMA_TABLE"
