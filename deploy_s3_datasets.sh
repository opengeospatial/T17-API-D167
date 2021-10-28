#!/usr/bin/env bash

## Global variables
DB_NAME='dbapi4'
DATE=$(date +%d%m%Y)
JSON_DIR='/opt/api4_jsons'
POINT_JSON_FILE="${JSON_DIR}/planet_osm_point-${DATE}.json"
POLYGON_JSON_FILE="${JSON_DIR}/planet_osm_polygon-${DATE}.json"

function requirements
{
  ## Installing jq package if it is not installed
  if ! dpkg -l jq &> /dev/null
    then
      echo "The package jq is not installed."
      exit 1
  fi

  ## Checking if AWS cli is installed
  if ! dpkg -l awscli &> /dev/null
    then
      echo "The package awscli is not installed."
      exit 1
  fi

  ## Creating the directory where the JSON files
  ## will be stored
  if [[ ! -d ${JSON_DIR} ]]
    then
      mkdir -pm 0755 ${JSON_DIR}
  fi
}

function get_planet_osm_point
{
  ## Local variables
  local TABLE_NAME='planet_osm_point'
  local ROW_LIMIT="${1}"
  local REGEX_ROW='^[0-9]+$'

  ## Checking that the variable ROW_LIMIT is a valid number
  if [[ ! ${ROW_LIMIT} =~ ${REGEX_ROW} ]]
    then
      echo "Invalid value for ROW_LIMIT"
      exit 1
  fi

  ## Getting all the records from the table 'planet_osm_point'
  psql -w -U postgres -p 5432 -h localhost ${DB_NAME} -t -o ${POINT_JSON_FILE} -c "SELECT row_to_json(fc) AS geojson FROM (SELECT 'FeatureCollection' As type, array_to_json(array_agg(f)) As features FROM (SELECT 'Feature' As type, ST_AsGeoJSON((ST_Transform (lg.way,4326)),15,0)::json As geometry, row_to_json((osm_id, name, place)::geojson_properties) As properties FROM planet_osm_point As lg limit ${ROW_LIMIT}) As f ) As fc;"

  ## Creating the directory where all the rows will be exported in json
  ## or cleaning the directory
  if [[ ! -d ${JSON_DIR}/${TABLE_NAME} ]]
    then
      mkdir -pm 0755 ${JSON_DIR}/${TABLE_NAME}
    else
      find ${JSON_DIR}/${TABLE_NAME}/ -type f -exec rm -f {} \;
  fi

  ## Getting the number of records in the array 'features'
  local NUM_ROWS=$(jq '.features | length' ${POINT_JSON_FILE})

  echo "Exporting the rows to independent json files..."

  ## Creating a json file for each row
  for ((row=0;row<${NUM_ROWS};row++))
    do
      FILE_NAME=$(jq '.features' ${POINT_JSON_FILE} | jq -r ".[${row}].properties.osm_id")
      jq '.features' ${POINT_JSON_FILE} | jq ".[${row}]" > ${JSON_DIR}/${TABLE_NAME}/${FILE_NAME}.json
    done

  echo "Exportation completed."

  ## Setting the right permissions
  chmod 0644 ${JSON_DIR}/${TABLE_NAME}/*.json
}

function get_planet_osm_polygon
{
  ## Local variables
  local TABLE_NAME='planet_osm_polygon'
  local ROW_LIMIT="${1}"
  local REGEX_ROW='^[0-9]+$'

  ## Checking that the variable ROW_LIMIT is a valid number
  if [[ ! ${ROW_LIMIT} =~ ${REGEX_ROW} ]]
    then
      echo "Invalid value for ROW_LIMIT"
      exit 1
  fi

  ## Getting all the records from the table 'planet_osm_point'
  psql -w -U postgres -p 5432 -h localhost ${DB_NAME} -t -o ${POLYGON_JSON_FILE} -c "SELECT row_to_json(fc) AS geojson FROM (SELECT 'FeatureCollection' As type, array_to_json(array_agg(f)) As features FROM (SELECT 'Feature' As type, ST_AsGeoJSON((ST_Transform (lg.way,4326)),15,0)::json As geometry, row_to_json((osm_id, name, place)::geojson_properties) As properties FROM planet_osm_polygon As lg limit ${ROW_LIMIT}) As f ) As fc;"

  ## Creating the directory where all the rows will be exported in json
  ## or cleaning the directory
  if [[ ! -d ${JSON_DIR}/${TABLE_NAME} ]]
    then
      mkdir -pm 0755 ${JSON_DIR}/${TABLE_NAME}
    else
      find ${JSON_DIR}/${TABLE_NAME}/ -type f -exec rm -f {} \;
  fi

  ## Getting the number of records in the array 'features'
  local NUM_ROWS=$(jq '.features | length' ${POLYGON_JSON_FILE})

  echo "Exporting the rows to independent json files..."

  ## Creating a json file for each row
  for ((row=0;row<${NUM_ROWS};row++))
    do
      FILE_NAME=$(jq '.features' ${POLYGON_JSON_FILE} | jq -r ".[${row}].properties.osm_id")
      jq '.features' ${POLYGON_JSON_FILE} | jq ".[${row}]" > ${JSON_DIR}/${TABLE_NAME}/${FILE_NAME}.json
    done

  echo "Exportation completed."

  ## Setting the right permissions
  chmod 0644 ${JSON_DIR}/${TABLE_NAME}/*.json
}

function upload_json {
  ## Local variables
  local BUCKET_NAME="${1}"
  local TABLE_NAME="${2}"

  cd ${JSON_DIR}/${TABLE_NAME}

  echo "Uploading the json files to AWS S3..."

  for file in $(find . -type f -name "*.json" | sed 's#^./##')
    do
      ## Getting the hash of the file
      local FILE_HASH=$(openssl md5 -binary ${file} | base64)

      ## Uploading to AWS S3
      aws s3api put-object \
        --bucket ${BUCKET_NAME} \
        --body ${file} \
        --key ${file} \
        --content-md5 ${FILE_HASH} \
        --storage-class STANDARD_IA \
        --content-type "application/json" \
        --acl public-read
    done

    echo "Upload completed."
}


## Running the requirements
requirements

## Checking which function should be executed
if [[ ${1} == 'point' ]]
  then
    get_planet_osm_point 10000
    upload_json 'ogc-points' 'planet_osm_point'
  elif [[ ${1} == 'polygon' ]]
    then
      get_planet_osm_polygon 10000
      upload_json 'ogc-polygons' 'planet_osm_polygon'
  else
      echo -e "Incorrect or miss argument. The options are: point or polygon.\n\tAn example: export_json point"
fi

