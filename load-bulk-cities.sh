#!/bin/bash

DB_HOST="localhost"
DB_PORT="5433"
DB_USER="postgres"
DB_NAME="test_gis"
DB_PASSWORD="postgres"
SCHEMA_TABLE="public.us_place"
SRID=4269
GEOM_COL="geom"
WORKDIR="$HOME/code/Source-US-GIS/archieve/us_places"

# List of all 50 states 
STATES=(
  01 02 04 05 06 08 09 10 11 12 13 15 16 17 18 19 20 21 22 23 24 25
  26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 44 45 46 47 48 49
  50 51 53 54 55 56
)

BASE_URL="https://www2.census.gov/geo/tiger/TIGER2020/PLACE"

mkdir -p "$WORKDIR"
cd "$WORKDIR" || exit 1

# Temporary SQL file to batch all COPY statements
SQL_FILE="$WORKDIR/all_us_places.sql"
: > "$SQL_FILE"  # clear or create fresh

# -----------------------------
# Loop through each state
# -----------------------------
for FIPS in "${STATES[@]}"; do
  ZIPFILE="tl_2020_${FIPS}_place.zip"
  STATE_DIR="${WORKDIR}/${FIPS}"
  mkdir -p "$STATE_DIR"

  # Download if not exists
  if [ ! -f "$STATE_DIR/$ZIPFILE" ]; then
    echo "Downloading $ZIPFILE..."
    curl -L -o "$STATE_DIR/$ZIPFILE" "$BASE_URL/$ZIPFILE"
  else
    echo "$ZIPFILE already exists, skipping download."
  fi

  # Unzip
  echo "Unzipping $ZIPFILE..."
  unzip -o "$STATE_DIR/$ZIPFILE" -d "$STATE_DIR"

  # Find .shp file
  SHP_FILE=$(find "$STATE_DIR" -maxdepth 1 -name "*.shp" | head -n1)
  if [ -z "$SHP_FILE" ]; then
    echo "No .shp file found in $STATE_DIR, skipping."
    continue
  fi

  # Determine mode: create table for first state, append for others
  if [ "$FIPS" == "01" ]; then
    MODE="-dD"  # drop/create with COPY
  else
    MODE="-aD"  # append with COPY
  fi

  echo "Preparing SQL for $SHP_FILE..."
  shp2pgsql -s $SRID $MODE -g $GEOM_COL "$SHP_FILE" "$SCHEMA_TABLE" >> "$SQL_FILE"
done

# -----------------------------
# Bulk load into Postgres
# -----------------------------
echo "Loading all data into $SCHEMA_TABLE..."
PGPASSWORD="$DB_PASSWORD" psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f "$SQL_FILE"

# -----------------------------
# Add spatial index + analyze
# -----------------------------
echo "Creating spatial index..."
PGPASSWORD="$DB_PASSWORD" psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME <<EOF
CREATE INDEX IF NOT EXISTS idx_us_place_geom ON $SCHEMA_TABLE USING gist ($GEOM_COL);
ANALYZE $SCHEMA_TABLE;
EOF

echo "✅ All states imported into $SCHEMA_TABLE with COPY (bulk mode)"
