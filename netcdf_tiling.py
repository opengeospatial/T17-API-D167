#!/user/bin/python3

"""NetCDF tiling script

This script is a proof of concept to apply the idea of tiling to
NetCDF files.

The script takes a NetCDF file and creates new NetCDF files containing
the values for the different zoom levels:

 * Level 0: one file
 * Level 1: four files
 * level 2: sixteen files

 and so on

This code is for demonstration purposes and it uses the sample file air.sig995.2012.nc
available at https://psl.noaa.gov/repository/entry/show?entryid=972f08b9-e4b1-4edf-94e8-5ad7c4d8b33d

"""

import numpy as np
from netCDF4 import Dataset

MAX_LEVEL = 4
WORKING_DIR = './'
NETCDF_FILE = 'air.sig995.2012.nc'
OUTPUTFILES_NAME = NETCDF_FILE.replace('.nc', '')

nc_f = WORKING_DIR + NETCDF_FILE
nc_fid = Dataset(nc_f, 'r')

# Extract data from NetCDF file
lats = nc_fid.variables['lat'][:]
lons = nc_fid.variables['lon'][:]
time = nc_fid.variables['time'][:]
air = nc_fid.variables['air'][:]

for this_level in range(0, MAX_LEVEL + 1):
    num_tiles_per_side = 2 ** this_level
    for lon_side_idx in range(0, num_tiles_per_side):
        lon_range = [round(len(lons)/num_tiles_per_side * lon_side_idx), round(len(lons)/num_tiles_per_side * (lon_side_idx + 1))]
        for lat_side_idx in range(0, num_tiles_per_side):
            lat_range = [round(len(lats)/num_tiles_per_side * lat_side_idx), round(len(lats)/num_tiles_per_side * (lat_side_idx + 1))]
            if lat_range[1] == len(lats): bbox = [ [ None, lats[lat_range[1]-1] ], [ None, lats[lat_range[0]] ] ]
            else: bbox = [ [ None, lats[lat_range[1]] ], [ None, lats[lat_range[0]] ] ]

            if lon_range[1] == len(lons) and lon_range[0] == 0:
                bbox[0][0] = -180.0
                bbox[1][0] = 180.0
            elif lon_range[1] == len(lons):
                bbox[0][0] = lons[lon_range[0]]
                bbox[1][0] = lons[0]
            else:
                bbox[0][0] = lons[lon_range[0]]
                bbox[1][0] = lons[lon_range[1]]
            if bbox[0][0] >= 180.0: bbox[0][0] -= 360.0
            if bbox[1][0] > 180.0: bbox[1][0] -= 360.0

            w_nc_fid = Dataset(WORKING_DIR + OUTPUTFILES_NAME + str(this_level) + '.' + str(lon_side_idx) + '.' + str(lat_side_idx) + '.nc', 'w', format='NETCDF4')
            w_nc_fid.title = nc_fid.title + ", level " + str(this_level)
            w_nc_fid.history = nc_fid.history + ". Modified by Skymantics for OGC Testbed 17 - API Experiments task in 2021."
            w_nc_fid.description = nc_fid.description + " Values are within bounding box " + str(bbox)
            w_nc_fid.platform = nc_fid.platform
            w_nc_fid.references = nc_fid.references

            w_nc_fid.createDimension('time', None)
            w_nc_fid.createDimension('lat', lat_range[1] - lat_range[0])
            w_nc_fid.createDimension('lon', lon_range[1] - lon_range[0])
            w_nc_dim_time = w_nc_fid.createVariable('time', nc_fid.variables['time'].dtype, ('time',), zlib=True)
            w_nc_dim_lat = w_nc_fid.createVariable('lat', nc_fid.variables['lat'].dtype, ('lat',), zlib=True)
            w_nc_dim_lon = w_nc_fid.createVariable('lon', nc_fid.variables['lon'].dtype, ('lon',), zlib=True)
            for ncattr in nc_fid.variables['time'].ncattrs(): w_nc_dim_time.setncattr(ncattr, nc_fid.variables['time'].getncattr(ncattr))
            for ncattr in nc_fid.variables['lat'].ncattrs(): w_nc_dim_lat.setncattr(ncattr, nc_fid.variables['lat'].getncattr(ncattr))
            for ncattr in nc_fid.variables['lon'].ncattrs(): w_nc_dim_lon.setncattr(ncattr, nc_fid.variables['lon'].getncattr(ncattr))
            
            w_nc_fid.variables['time'][:] = time
            w_nc_fid.variables['lat'][:] = lats[lat_range[0]:lat_range[1]]
            w_nc_dim_lat.actual_range = [ np.amin(lats[lat_range[0]:lat_range[1]]), np.amax(lats[lat_range[0]:lat_range[1]]) ]
            w_nc_fid.variables['lon'][:] = lons[lon_range[0]:lon_range[1]]
            w_nc_dim_lon.actual_range = [ np.amin(lons[lon_range[0]:lon_range[1]]), np.amax(lons[lon_range[0]:lon_range[1]]) ]

            w_nc_var = w_nc_fid.createVariable('air', nc_fid.variables['air'].dtype, ('time', 'lat', 'lon'))
            for ncattr in nc_fid.variables['air'].ncattrs(): w_nc_var.setncattr(ncattr, nc_fid.variables['air'].getncattr(ncattr))
            w_nc_fid.variables['air'][:] = air[:, lat_range[0]:lat_range[1], lon_range[0]:lon_range[1]]
            w_nc_fid.close()

