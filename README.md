# T17-API-D167 Data Backend and Deployment

This repository provides scripts and documentation developed for D167 at OGC Testbed 17 - API Experiments task.

They cover the following use cases:

* Deploy PostGIS in the cloud (AWS, CloudSigma, CloudFerro)
* Deploy AWS S3 GeoJSON objects
* Generate and deploy a tiles server (Docker and one-click service options)

Please note this repository is under development.

## Tiles generation and tiles server

Tiles generation and publishing is essential for any client showing features in a graphical way. Tiles can be imported from external repositories but we are documenting how to publish them from a server/cloud. We have explored how to publish OSM raster tiles on an Ubuntu server and on a docker container. Both options allow to deploy a tile server both locally and in a cloud environment.

The docker container option described in this documentation will render the tiles before launching the service, and the Ubuntu server option will generate the tiles on demand.

### Prerequisites

Ubuntu 20.04 is the base operating system in both cases. In addition, Docker and Docker compose are used for the docker case. The process to generate the tiles from OSM requires a number of open source tools. In addition to a PostgreSQL database, this includes:

* PostGIS Extensions: a spatial database extender for PostgreSQL object-relational database
* osm2pgsql: a tool that converts OSM data to postGIS-enabled PostgreSQL databases
* mapnik: a map-rendering toolkit that includes bindings in Node, Python, and C++
* renderd: a rendering daemon used with mapnik and OSM
* mod_tile: an Apache module that renders and serves map tiles
* OpenLayers/Leaflef: a mapping Js library that includes markers and tiled layers

### Using Docker containers to render OSM tiles

OSM provides an overview on how to install, configure, and use these tools from scratch to get the tiles rendered. For the purpose of this "how to", we are going to use a container image with the set tools above that are needed to create and generate the map tiles from the OSM data.

For this example, you can use a [container image](https://github.com/ncareol/osm-tiles-docker) from GitHub, built by the [National Center for Atmospheric Research Earth Observing Laboratory](https://www.eol.ucar.edu/earth-observing-laboratory) that is based on the openstreetmap-docker-files image. The process is outlined below:

First of all, you'll need to obtain the OSM data you want to serve, you can get it from [geofabrik](https://download.geofabrik.de/), you just need to search what set of data you need and click in the download link. For this example we use the [Spain data file](https://download.geofabrik.de/europe/spain-latest.osm.pbf). Download it, and place it into the root of your project.

In the folder you placed the data file, create the Docker Compose file (must be named docker-compose.yml), following the [example in this repository](https://github.com/opengeospatial/T17-API-D167/blob/master/docker-compose.yml).

If you choose another set of data, replace "spain-latest.osm.pbf" by your file.

Once you have set up the docker-compose file, run the following commands:

1. Initiate the PostgreSQL database

```
docker-compose run osm initdb
```

2. Parse and import the PBF data into the database

```
docker-compose run osm import
```

This step will take a while. For example, using an EC2 c5.large instance (2CPU and 4GB RAM) would need more like 7 hours, and might not even complete the parsing proccess.

3. Render the tiles

```
docker-compose run osm render
```

Take into account the NCAR EOL warning at the container-image wiki at this stage. Ensure /var/lib/mod_tile directory exists and Docker’s containers www-data user has write permissions before rendering. This can be done by accessing the Docker image:

```
$ docker-compose run osm bash
docker # mkdir -p /var/lib/mod_tile/default
docker # chown www-data /var/lib/mod_tile/default
```
At this point, tiles are rendered and we are ready to start serving the map tiles. The container image also contains an Apache module with mod_tile server. Let’s bring it up with:

```
docker-compose up osm
```

That's all, now, you just need to open a web browsere and access to your instance through port 8000 such as `http://localhost:8000` or `http://your-domain-name.com:8000`

### The 'one-click' tiles server using an Ubuntu machine

The goal is for new developers to be able to quickly deploy an operational tiles server and be able to focus their time on exploring and playing with more value-added datasets. We use Open Street Maps as the data source to generate the tiles. All software used is open source and freely available.

There is a [switch2osm tutorial](https://switch2osm.org/serving-tiles/manually-building-a-tile-server-20-04-lts/) describing all the steps in detail. In order to facilitate the automation we are facilitating [a script that automates all these steps](https://github.com/opengeospatial/T17-API-D167/blob/master/one-click_tiles_server.sh). Using this script, the only action required to deploy a tiles server is to download the script (and set up the permissions to executable), adapt the values in the script variables (country, username, hardware specs) and launch it. This process is way simpler and more maintainable than using docker.
It is prepared to work on a freshly installed Ubuntu server (version 20.04, the latest stable) and the steps it takes are roughly the following:

1. It installs/compiles all the software dependencies
2. It installs a postgreSQL/postGIS database and sets it up
3. It downloads and configures a stylesheet
4. It downloads OSM data for the specific country and inserts it into the database
5. It downloads additional shapefiles and fonts
6. It sets up apache server with renderd
7. It launches apache and renderd
8. Clients can now add a tilelayer with the server IP address (being it localhost or a valid IP or domain) and request tiles

The user does not need to interact with the script. Everything happens in the background.

The process is set to generate raster tiles on demand, but it should be possible to generate vector tiles with some changes.

The last part of the process sets up a cache. Instead of using the method documented in OSM (using tilecache, that stores the generated tiles in the server and risks of consuming large space in the hd), we opted to use an Apache module that caches the generated tiles in the client's browser (by default tiles will be cached for 14 days).

## GeoJSON objects deployment in AWS S3 

Deploying GeoJSON objects in AWS is not a particularly complex task, although it requires familiarity with some tools and commands. For this deliverable, Skymantics has worked with a scenario that a series of features stored in a PostgreSQL/PostGIS database need to be exported to GeoJSON and published in an AWS S3 bucket. All the main steps in this process have been coded in a shell script that makes a request from a specific table, stores the results in independent files and uploads them to an AWS S3 bucket.

The script has functions to review that the environment meets the requirements, to obtain the data from an SQL query and upload them to an AWS S3 bucket, and to add new features as a new dataset.

### Prerequisites

1. The script needs to be executed in a EC2 AWS instance, set up to store datasets.
1. The instance needs to have an associated role, in order to avoid authentication, increasing thus the security.
1. The AWS S3 bucket needs permissions to upload objects and modify an object's ACLs (in order to make the object public).
1. The instance needs access to the Internet.
1. Packages `jq` y `awscli` must be installed.

### Limitations

This script is configured to use the following buckets:

* ogc-points
* ogc-polygons

Each bucket is generated from a dataset stored in a database, points or polygons respectively. You can modify it to adapt to your particular case.

Existing JSON files in AWS S3 will not be deleted.

### Script usage

Once the environment meets the requirements, follow these steps to launch the script:

1. Upload the script to the location where you want to execute it.

2. Copy the script to folder `/usr/local/sbin/`.

```
sudo cp -v deploy_s3_datasets.sh /usr/local/sbin/
```

**NOTE:** It can be copied to a different directory, as long as it is included in variable `PATH`.

3. Set permissions for execution.

```
sudo chmod 0750 /usr/local/sbin/deploy_s3_datasets.sh
```

4. Modify the global variables in the script, with are located at the beginning of the file. The most important variables are:

    | Variable           | Description                                                                    |
    |--------------------|--------------------------------------------------------------------------------|
    | DB_NAME            | Name of the database withh the datasets to extract                             |
    | JSON_DIR           | Directory to save the JSON output files                                        |
    | POINT_JSON_FILE    | JSON file with the content of the `point` dataset query                        |
    | POLYGON_JSON_FILE  | JSON file with the content of the `polygons` dataset query                     |

**NOTE:** All files in the directory defined in variable `JSON_DIR` will be deleted.

5. Proceed to execute the script, passing the dataset we are interested in as argument (examples for dataset point and dataset polygons respectively). This command will extract the data from the database, package it as GeoJSON and upload it to AWS S3 in one go:

```
sudo deploy_s3_datasets.sh point
```

or

```
sudo deploy_s3_datasets.sh polygons
```

**NOTE:** If you want to execute it in debug mode, launch the script in the following manner:

```
sudo bash -x /usr/local/sbin/deploy_s3_datasets.sh point
```

or

```
sudo bash -x /usr/local/sbin/deploy_s3_datasets.sh polygons
```

6. Check that the files are properly uplodaded. You have two different options for that:

a) From AWS console (first access S3 service and then the bucket).
b) Using the AWS S3 bucket's URL, for example:

* List the objects in the bucket: https://ogc-points.s3.us-east-2.amazonaws.com/ or https://ogc-polygons.s3.us-east-2.amazonaws.com/
* One specific object in the bucket: https://ogc-points.s3.us-east-2.amazonaws.com/101144261.json o https://ogc-polygons.s3.us-east-2.amazonaws.com/548865641.json

### Troubleshooting

In case of issues during the script's execution, you need to identify which function is failing, as it could be a problem with the connection to the PostgreSQL database, the JSON parsing (`get_planet_osm_` functions) or an access problem to the AWS S3 bucket (`upload_json` function).

If the later, check whether the user can query the AWS S3 bucket, for example:

```
aws s3 ls ogc-points
```

or

```
aws s3 ls ogc-polygons
```

If after executing that command there is an issue whatsoever, then you need to contact the system administrator responsible for AWS S3 and provide all the information on the issue, such as the error message that is prompted after the previous command or the log of the script execution in debug mode.
