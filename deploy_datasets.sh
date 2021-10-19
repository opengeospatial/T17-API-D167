#!/bin/bash

# Global variables
USERNAME='apipostgres'
PROJECTROOT="/home/${USERNAME}"
ZONEPBF='europe'
COUNTRYPBF='spain'
FILENAME="$COUNTRYPBF-latest.osm.pbf"
MEMORYLIMIT=2000 # Allocate 2 Gb of memory to osm2pgsql to the import process. If you have less memory you could try a smaller number, and if the import process is killed because it runs out of memory you’ll need to try a smaller number or a smaller OSM extract..
NBCPUS=1 # Use 1 CPU. If you have more cores available you can use more.
DB_NAME='db_api01'
DBA_NAME='dba_api01'
DB_EXTERNAL=1
DB_AUTH_FILE='/root/.sql'

function postgresql_install
{
  local DB_MAIN_CONFIG='/etc/postgresql/12/main/postgresql.conf'
  local DB_ACLS_CONFIG='/etc/postgresql/12/main/pg_hba.conf'

  locale-gen "es_ES.UTF-8"
  sudo apt-get install -y postgresql postgresql-contrib postgis postgresql-12-postgis-3 postgresql-12-postgis-3-scripts

  ## Allowing connections without password in local
  sudo sed -i '96s/md5/trust/' ${DB_ACLS_CONFIG}

  if [[ ${DB_EXTERNAL} -eq 1 ]];
    then
      echo "listen_addresses = '*'" | sudo tee -a ${DB_MAIN_CONFIG}
      echo 'host    all    all    0.0.0.0/0    md5' | sudo tee -a ${DB_ACLS_CONFIG}
  fi

  sudo systemctl restart postgresql
  sudo systemctl enable postgresql
}

function database_setup
{

  ## Creating the database user
  sudo -i -u postgres createuser ${DBA_NAME}
  sudo -i -u postgres psql -w -U postgres -p 5432 -h localhost \
    -c "ALTER USER ${DBA_NAME} PASSWORD '${DBA_PASSWORD}'"

  ## Creating the database
  sudo -i -u postgres createdb -E UTF8 -O ${DBA_NAME} ${DB_NAME}

  ## Tunning the database
  sudo -i -u postgres psql -w -U postgres -p 5432 -h localhost ${DB_NAME} \
    -c 'CREATE EXTENSION postgis; CREATE EXTENSION hstore;'
  sudo -i -u postgres psql -w -U postgres -p 5432 -h localhost ${DB_NAME} \
    -c 'ALTER TABLE geometry_columns OWNER TO '${DBA_NAME}'; ALTER TABLE spatial_ref_sys OWNER TO '${DBA_NAME}';'
}

function parser_install
{
  sudo apt-get install -y osm2pgsql wget git npm

  # Stylesheet configuration
  mkdir ${PROJECTROOT}/src
  cd ${PROJECTROOT}/src

  git clone git://github.com/gravitystorm/openstreetmap-carto.git
  cd openstreetmap-carto

  sudo npm install -g carto
}

function parser_init
{
  sudo -u ${USERNAME} carto ${PROJECTROOT}/src/openstreetmap-carto/project.mml > mapnik.xml

  mkdir ${PROJECTROOT}/data
  cd ${PROJECTROOT}/data

  ## Ensuring that there is not any PBF file
  if [[ -f ${PROJECTROOT}/data/${FILENAME} ]]
    then
      rm ${PROJECTROOT}/data/${FILENAME}
  fi

  wget https://download.geofabrik.de/${ZONEPBF}/${FILENAME}

  # Parsing pbf file
  sudo -i -u postgres osm2pgsql -d ${DB_NAME} --create --slim  -G --hstore \
    --tag-transform-script ${PROJECTROOT}/src/openstreetmap-carto/openstreetmap-carto.lua \
    -C ${MEMORYLIMIT} --number-processes ${NBCPUS} -S ${PROJECTROOT}/src/openstreetmap-carto/openstreetmap-carto.style \
    ${PROJECTROOT}/data/${FILENAME}

  sudo chown -R ${USERNAME}:${USERNAME} ${PROJECTROOT}
}

function dataset_geojson_places
{
  local SQL_FILE="${PROJECTROOT}/geojson_places.sql"

  cat <<EOF > ${SQL_FILE}
-- CREATE TABLE
CREATE TABLE IF NOT EXISTS geojson_places
(
    gid integer,
    geom geometry,
    osm_id varchar,
    place varchar,
    name varchar
);

-- SELECT DATA FROM planet_osm_point AND INSERT DATA INTO geojson_places
INSERT INTO geojson_places
WITH data AS (select row_to_json(fc)
from (
    select 'FeatureCollection' as "type", array_to_json(array_agg(f)) as "features"
    from (
        select
            'Feature' as "type", ST_AsGeoJSON(ST_Transform(way, 4326), 6) :: json as "geometry",
            (
                select json_strip_nulls(row_to_json(t))
                from (
                    select
                        osm_id, place, name
                ) t
            ) as "properties"
        from planet_osm_point
        where
          "place" is not null and
          "natural" is null
    ) as f
) as fc)
SELECT
  row_number() OVER () AS gid,
  ST_AsText(ST_GeomFromGeoJSON(feat->>'geometry')) AS geom,
  feat->'properties' -> 'osm_id' AS osm_id,
  feat->'properties' -> 'place' AS place,
  feat->'properties' -> 'name' AS name
FROM (
  SELECT json_array_elements(row_to_json->'features') AS feat
  FROM data
) AS f;
EOF

  ## Importing the SQL statements
  sudo -i -u postgres psql -w -U postgres -p 5432 -h localhost -d ${DB_NAME} < ${SQL_FILE}

  ## Grant privileges to the new table
  sudo -i -u postgres psql -w -U postgres -p 5432 -h localhost -d ${DB_NAME} \
    -c "GRANT ALL PRIVILEGES ON geojson_places TO ${DBA_NAME}"

  ## Removing the temporal sql file
  rm -f ${SQL_FILE}
}

function dataset_geojson_polygons
{
  local SQL_FILE="${PROJECTROOT}/geojson_polygons.sql"

  cat <<EOF > ${SQL_FILE}
-- CREATE TABLE
CREATE TABLE IF NOT EXISTS geojson_polygons
(
    gid integer,
    geom geometry,
    osm_id varchar,
    place varchar,
    name varchar
);

-- SELECT DATA FROM planet_osm_point AND INSERT DATA INTO geojson_places
INSERT INTO geojson_polygons
WITH data AS (select row_to_json(fc)
from (
    select 'FeatureCollection' as "type", array_to_json(array_agg(f)) as "features"
    from (
        select
            'Feature' as "type", ST_AsGeoJSON(ST_Transform(way, 4326), 6) :: json as "geometry",
            (
                select json_strip_nulls(row_to_json(t))
                from (
                    select
                        osm_id, place, name
                ) t
            ) as "properties"
        from planet_osm_polygon limit 500000
    ) as f
) as fc)
SELECT
  row_number() OVER () AS gid,
  ST_AsText(ST_GeomFromGeoJSON(feat->>'geometry')) AS geom,
  feat->'properties' -> 'osm_id' AS osm_id,
  feat->'properties' -> 'place' AS place,
  feat->'properties' -> 'name' AS name
FROM (
  SELECT json_array_elements(row_to_json->'features') AS feat
  FROM data
) AS f;
EOF

  ## Importing the SQL statements
  sudo -i -u postgres psql -w -U postgres -p 5432 -h localhost -d ${DB_NAME} < ${SQL_FILE}

  ## Grant privileges to the new table
  sudo -i -u postgres psql -w -U postgres -p 5432 -h localhost -d ${DB_NAME} \
    -c "GRANT ALL PRIVILEGES ON geojson_polygons TO ${DBA_NAME}"

  ## Removing the temporal sql file
  rm -f ${SQL_FILE}
}

function dataset_geojson_waterways
{
  local SQL_FILE="${PROJECTROOT}/geojson_polygons.sql"

  cat <<EOF > ${SQL_FILE}
-- CREATE TABLE
CREATE TABLE IF NOT EXISTS geojson_waterways
(
    gid integer,
    geom geometry,
    osm_id varchar,
    waterway varchar,
    name varchar
);

-- SELECT DATA FROM planet_osm_line AND INSERT DATA INTO geojson_waterways
INSERT INTO geojson_waterways
WITH data AS (select row_to_json(fc)
from (
    select 'FeatureCollection' as "type", array_to_json(array_agg(f)) as "features"
    from (
        select
            'Feature' as "type", ST_AsGeoJSON(ST_Transform(way, 4326), 6) :: json as "geometry",
            (
                select json_strip_nulls(row_to_json(t))
                from (
                    select
                        osm_id, waterway, name
                ) t
            ) as "properties"
        from planet_osm_line
    where waterway is not null and name is not null
    ) as f
) as fc)
SELECT
  row_number() OVER () AS gid,
  ST_AsText(ST_GeomFromGeoJSON(feat->>'geometry')) AS geom,
  feat->'properties' -> 'osm_id' AS osm_id,
  feat->'properties' -> 'waterway' AS waterway,
  feat->'properties' -> 'name' AS name
FROM (
  SELECT json_array_elements(row_to_json->'features') AS feat
  FROM data
) AS f;
EOF

  ## Importing the SQL statements
  sudo -i -u postgres psql -w -U postgres -p 5432 -h localhost -d ${DB_NAME} < ${SQL_FILE}

  ## Grant privileges to the new table
  sudo -i -u postgres psql -w -U postgres -p 5432 -h localhost -d ${DB_NAME} \
    -c "GRANT ALL PRIVILEGES ON geojson_waterways TO ${DBA_NAME}"

  ## Removing the temporal sql file
  rm -f ${SQL_FILE}
}

## Asking for database password
if [[ ! -f ${DB_AUTH_FILE} ]] || [[ -z ${DB_AUTH_FILE} ]]
  then
    read -s -p "Enter the password for the database user '${DBA_NAME}': " DBA_PASSWORD
    echo -e "Username: ${DBA_NAME}\nPassword: ${DBA_PASSWORD}" | sudo tee ${DB_AUTH_FILE}
    sudo chmod 0400 ${DB_AUTH_FILE}
fi

## Creating a local user where all the parser data will be stored
if ! grep -iq "${USERNAME}" /etc/passwd
  then
    sudo useradd -m -d /home/${USERNAME} -s /bin/bash -G sudo ${USERNAME}
fi

## Running the functions
postgresql_install
database_setup
parser_install
parser_init
dataset_geojson_places
dataset_geojson_polygons
dataset_geojson_waterways
