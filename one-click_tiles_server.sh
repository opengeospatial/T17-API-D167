#!/bin/bash

# Config vars
USERNAME=renderaccount
PROJECTROOT="/home/$USERNAME"
ZONEPBF=europe
COUNTRYPBF=spain
FILENAME=$COUNTRYPBF-latest.osm.pbf
MEMORYLIMIT=2000 # Allocate 2 Gb of memory to osm2pgsql to the import process. If you have less memory you could try a smaller number, and if the import process is killed because it runs out of memory you’ll need to try a smaller number or a smaller OSM extract..
NBCPUS=1 # Use 1 CPU. If you have more cores available you can use more.

sudo useradd -m -d /home/$USERNAME -s /bin/bash -G sudo $USERNAME

# Installing dependencies
sudo apt-get -y install libboost-all-dev git tar unzip wget bzip2 build-essential autoconf libtool libxml2-dev libgeos-dev libgeos++-dev libpq-dev libbz2-dev libproj-dev munin-node munin protobuf-c-compiler libfreetype6-dev libtiff5-dev libicu-dev libgdal-dev libcairo2-dev libcairomm-1.0-dev apache2 apache2-dev libagg-dev liblua5.2-dev ttf-unifont lua5.1 liblua5.1-0-dev

# Installing postgresql / postgis
locale-gen "es_ES.UTF-8"
sudo apt-get -y install postgresql postgresql-contrib postgis postgresql-12-postgis-3 postgresql-12-postgis-3-scripts
sudo sed -i '96s/md5/trust/' /etc/postgresql/12/main/pg_hba.conf
sudo systemctl restart postgresql


# Create a postgis database. The defaults of various programs assume the database is called gis and we will use the same convention in this script
sudo -i -u postgres createuser $USERNAME # answer yes for superuser (although this isn't strictly necessary)
sudo -i -u postgres createdb -E UTF8 -O $USERNAME gis
sudo -i -u postgres psql -w -U postgres -p 5432 -h localhost gis -c 'CREATE EXTENSION postgis; CREATE EXTENSION hstore;'
sudo -i -u postgres psql -w -U postgres -p 5432 -h localhost gis -c 'ALTER TABLE geometry_columns OWNER TO '$USERNAME'; ALTER TABLE spatial_ref_sys OWNER TO '$USERNAME';'

# Installing osm2pgsql
sudo apt-get -y install osm2pgsql
# Mapnik
sudo apt-get -y install autoconf apache2-dev libtool libxml2-dev libbz2-dev libgeos-dev libgeos++-dev libproj-dev gdal-bin libmapnik-dev mapnik-utils python3-mapnik python3-psycopg2

# Install mod_tile and renderd
# Compile the mod_tile source code:
mkdir $PROJECTROOT/src
cd $PROJECTROOT/src
git clone -b switch2osm git://github.com/SomeoneElseOSM/mod_tile.git
cd mod_tile
./autogen.sh
./configure
make
sudo make install
sudo make install-mod_tile
sudo ldconfig

sudo sed -i 's#URI=/hot/#URI=/tileserver/#' $PROJECTROOT/src/mod_tile/renderd.conf

# Stylesheet configuration
cd $PROJECTROOT/src
git clone git://github.com/gravitystorm/openstreetmap-carto.git
cd openstreetmap-carto

sudo apt-get -y install npm
sudo npm install -g carto

sudo -u $USERNAME carto project.mml > mapnik.xml

# Loading data
mkdir $PROJECTROOT/data
cd $PROJECTROOT/data
wget https://download.geofabrik.de/$ZONEPBF/$FILENAME


# Parsing pbf file
sudo -i -u $USERNAME osm2pgsql -d gis --create --slim  -G --hstore --tag-transform-script $PROJECTROOT/src/openstreetmap-carto/openstreetmap-carto.lua -C $MEMORYLIMIT --number-processes $NBCPUS -S $PROJECTROOT/src/openstreetmap-carto/openstreetmap-carto.style $PROJECTROOT/data/$FILENAME

## Creating indexes
sudo -i -u $USERNAME psql -p 5432 -h localhost -d gis -f $PROJECTROOT/src/openstreetmap-carto/indexes.sql

# Shapefile download
sudo chown -R $USERNAME:$USERNAME $PROJECTROOT
cd $PROJECTROOT/src/openstreetmap-carto/
sudo -u $USERNAME scripts/get-external-data.py

# Fonts
sudo apt-get -y install fonts-noto-cjk fonts-noto-hinted fonts-noto-unhinted ttf-unifont

# Setting up the webserver
# Configuring renderd
sudo sed -i "s/num_threads=.*/num_threads=4/" /usr/local/etc/renderd.conf
sudo head -5 /usr/local/etc/renderd.conf | egrep -qx "XML=$PROJECTROOT/src/openstreetmap-carto/mapnik.xml" || sudo sed -i "s#\[renderd\]#\[renderd\]\nXML=$PROJECTROOT/src/openstreetmap-carto/mapnik.xml#" /usr/local/etc/renderd.conf
sudo head -5 /usr/local/etc/renderd.conf | egrep -x 'URI=/tileserver/' || sudo sed -i "s#\[renderd\]#\[renderd\]\nURI=/tileserver/#" /usr/local/etc/renderd.conf
sudo sed -i 's#URI=/hot/#URI=/tileserver/#' /usr/local/etc/renderd.conf


# Configuring Apache
sudo mkdir /var/lib/mod_tile
sudo chown $USERNAME /var/lib/mod_tile

sudo mkdir /var/run/renderd
sudo chown $USERNAME /var/run/renderd

if [ ! -f /etc/apache2/conf-available/mod_tile.conf ]; then echo 'LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so' | sudo tee /etc/apache2/conf-available/mod_tile.conf; fi
sudo a2enconf mod_tile

sudo sed -i "s#ServerAdmin webmaster@localhost#ServerAdmin webmaster@localhost\n\n\tLoadTileConfigFile /usr/local/etc/renderd.conf\n\tModTileRenderdSocketName /var/run/renderd/renderd.sock\n\t\# Timeout before giving up for a tile to be rendered\n\tModTileRequestTimeout 0\n\t\# Timeout before giving up for a tile to be rendered that is otherwise missing\n\tModTileMissingRequestTimeout 30\n#" /etc/apache2/sites-available/000-default.conf

sudo a2enmod rewrite
sudo systemctl restart apache2

# First time (just for debug, -f means foregound)
# sudo -u $USERNAME renderd -f -c /usr/local/etc/renderd.conf > renderd-log

# Running renderd in the background
sudo cp $PROJECTROOT/src/mod_tile/debian/renderd.init /etc/init.d/renderd
sudo chmod u+x /etc/init.d/renderd
sudo cp $PROJECTROOT/src/mod_tile/debian/renderd.service /lib/systemd/system/

# Starting and enabling
sudo systemctl enable renderd
sudo systemctl restart renderd


# Adding cache system (https://httpd.apache.org/docs/current/mod/mod_expires.html)
sudo a2enmod headers
sudo a2enmod expires

sudo echo '<IfModule mod_expires.c>
ExpiresActive On
FileETag None
ExpiresDefault "access plus 14 days"
ExpiresByType image/jpg "access plus 1 month"
ExpiresByType image/gif "access plus 1 month"
ExpiresByType image/jpeg "access plus 1 month"
ExpiresByType image/png "access plus 1 month"
ExpiresByType text/css "access plus 1 month"
ExpiresByType application/pdf "access plus 1 month"
ExpiresByType text/javascript "access plus 1 month"
ExpiresByType text/x-javascript "access plus 1 month"
ExpiresByType application/javascript "access plus 1 month"
ExpiresByType application/x-shockwave-flash "access plus 1 month"
ExpiresByType text/css "now plus 1 month"
ExpiresByType image/ico "access plus 1 month"
ExpiresByType image/x-icon "access plus 1 month"
ExpiresByType text/html "access plus 1 days"
</IfModule>' >> /etc/apache2/apache2.conf

sudo systemctl restart apache2
