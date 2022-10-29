#!/bin/bash
# ---------------
# background_layers.sh
# extract background info for crossing assessments digital field form

# usage: specify watershed groups of interest as a comma separated, single quoted string
# eg
# $ ./background_layers.sh "'VICT','COWN'"
# ---------------

set -euxo pipefail

# check that watershed group code is provided as argument
if [ $# -eq 0 ]
  then
    echo "No arguments supplied - provide list of watershed_group_code values for watersheds of interest"
    exit 1
fi

BCGW_SOURCES="whse_fish.fiss_fish_obsrvtn_pnt_sp \
    whse_fish.fiss_obstacles_pnt_sp \
    whse_fish.fiss_stream_sample_sites_sp \
    whse_imagery_and_base_maps.mot_culverts_sp \
    whse_fish.pscis_assessment_svw \
    whse_fish.pscis_design_proposal_svw \
    whse_fish.pscis_habitat_confirmation_svw \
    whse_fish.pscis_remediation_svw \
    whse_basemapping.gba_railway_tracks_sp \
    whse_forest_tenure.ften_road_section_lines_svw \
    whse_basemapping.gba_transmission_lines_sp"

# remove existing file if present
rm -f background_layers.gpkg

# ---------------
# initialize the geopackage with watershed group boundary, and get the extent 
# ---------------
bcdata dump WHSE_BASEMAPPING.FWA_WATERSHED_GROUPS_POLY \
    --query "WATERSHED_GROUP_CODE in ($1)" | \
    ogr2ogr -f GPKG background_layers.gpkg \
        -t_srs EPSG:3005 \
        -nln fwa_watershed_groups_poly \
        /vsistdin/

# get bounding box of watershed groups in albers and in lat/lon
BOUNDS=$(fio info background_layers.gpkg --layer fwa_watershed_groups_poly --bounds)
BOUNDS_LL=$(echo "[$BOUNDS]" | tr ' ', ',' | rio transform --src_crs EPSG:3005 --dst_crs EPSG:4326 | tr -d '[] ')

# ---------------
# get bcfishpass layers
# ---------------
ogr2ogr -f GPKG background_layers.gpkg \
    -update \
    -t_srs EPSG:3005 \
    -dim XY \
    -spat $BOUNDS \
    -spat_srs EPSG:3005 \
    /vsizip//vsicurl/https://www.hillcrestgeo.ca/outgoing/fishpassage/data/bcfishpass/outputs/bcfishpass.gdb.zip \
    crossings

ogr2ogr -f GPKG background_layers.gpkg \
    -update \
    -t_srs EPSG:3005 \
    -dim XY \
    -spat $BOUNDS \
    -sql "select segmented_stream_id,
     linear_feature_id,
     edge_type,
     blue_line_key,
     watershed_key,
     watershed_group_code,
     downstream_route_measure,
     length_metre,
     waterbody_key,
     wscode_ltree,
     localcode_ltree,
     gnis_name,
     stream_order,
     stream_magnitude,
     gradient,
     feature_code,
     upstream_route_measure,
     upstream_area_ha,
     map_upstream,
     channel_width,
     mad_m3s,
     barriers_anthropogenic_dnstr,
     barriers_pscis_dnstr,
     barriers_remediated_dnstr,
     barriers_bt_dnstr,
     barriers_ch_co_sk_dnstr,
     barriers_ch_co_sk_b_dnstr,
     barriers_pk_dnstr,
     barriers_st_dnstr,
     barriers_wct_dnstr,
     obsrvtn_pnt_distinct_upstr,
     obsrvtn_species_codes_upstr,
     access_model_bt,
     access_model_ch_co_sk,
     access_model_ch_co_sk_b,
     access_model_st,
     access_model_wct,
     cast(spawning_model_ch as boolean) as spawning_model_ch,
     cast(spawning_model_co as boolean) as spawning_model_co,
     cast(spawning_model_sk as boolean) as spawning_model_sk,
     cast(spawning_model_st as boolean) as spawning_model_st,
     cast(spawning_model_wct as boolean) as spawning_model_wct,
     cast(rearing_model_ch as boolean) as rearing_model_ch,
     cast(rearing_model_co as boolean) as rearing_model_co,
     cast(rearing_model_sk as boolean) as rearing_model_sk,
     cast(rearing_model_st as boolean) as rearing_model_st,
     cast(rearing_model_wct as boolean) as rearing_model_wct,
     geom
     from streams
    " \
    /vsizip//vsicurl/https://www.hillcrestgeo.ca/outgoing/fishpassage/data/bcfishpass/outputs/bcfishpass.gdb.zip
    

# ---------------
# get bcgw layers
# ---------------
for layer in $BCGW_SOURCES; do
    bcdata dump $layer --bounds "$BOUNDS" --bounds-crs EPSG:3005 | \
    ogr2ogr -f GPKG background_layers.gpkg \
        -update \
        -t_srs EPSG:3005 \
        -nln $layer \
        -dim XY \
        /vsistdin/
done

# ---------------
# get named streams from fwapg
# ---------------
ogr2ogr -f GPKG background_layers.gpkg \
    -update \
    -t_srs EPSG:3005 \
    -nln fwa_named_streams \
    "https://features.hillcrestgeo.ca/fwa/collections/whse_basemapping.fwa_named_streams/items.json?bbox=$BOUNDS_LL"

# ---------------
# get DRA
# (use ftp rather than bcgw so the attributes match what is in bcfishpass)
# ---------------
wget --trust-server-names -qN ftp://ftp.geobc.gov.bc.ca/sections/outgoing/bmgs/DRA_Public/dgtl_road_atlas.gdb.zip
ogr2ogr -f GPKG background_layers.gpkg \
    -update \
    -t_srs EPSG:3005 \
    -nln transport_line \
    -dim XY \
    -spat $BOUNDS \
    -spat_srs EPSG:3005 \
    dgtl_road_atlas.gdb.zip \
    TRANSPORT_LINE

echo 'Data extract complete, see background_layers.gpkg'