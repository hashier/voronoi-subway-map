#!/usr/bin/env fish

# Fetches worldwide subway/rail station data from Overpass API
# Saves raw responses to data/raw/ and normalized JSON to data/

set script_dir (status dirname)
set data_dir $script_dir/../data
set raw_dir $data_dir/raw
mkdir -p $data_dir $raw_dir

set -l modes \
    'subway-nodes' '[out:json][timeout:180];node["station"="subway"];out body;' \
    'subway-all' '[out:json][timeout:180];nwr["station"="subway"];out body center;' \
    'subway-broad' '[out:json][timeout:180];(nwr["station"="subway"];nwr["railway"="station"]["subway"="yes"];);out body center;' \
    'all-rail' '[out:json][timeout:180];(nwr["station"="subway"];nwr["railway"="station"]["subway"="yes"];nwr["station"~"light_rail|monorail"];nwr["railway"~"tram_stop|halt"];);out body center;'

for i in (seq 1 2 (count $modes))
    set name $modes[$i]
    set query $modes[(math $i + 1)]
    set rawfile $raw_dir/$name.json
    set outfile $data_dir/$name.json

    echo "Fetching $name..."
    curl -i --max-time 300 \
        --data-urlencode "data=$query" \
        'https://overpass-api.de/api/interpreter' \
        -o $rawfile

    if test $status -ne 0
        echo "  ERROR: curl failed for $name"
        continue
    end

    jq -f $script_dir/normalize.jq $rawfile > $outfile

    if test $status -ne 0
        echo "  ERROR: jq failed for $name"
        continue
    end

    set count (jq length $outfile)
    set raw_size (ls -lh $rawfile | awk '{print $5}')
    set size (ls -lh $outfile | awk '{print $5}')
    echo "  $name: $count stations, $size (raw: $raw_size)"
end

echo "Done."
