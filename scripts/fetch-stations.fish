#!/usr/bin/env fish

# Fetches worldwide subway/rail station data from Overpass API
# Downloads in 10-degree longitude strips for reliability
# Saves raw responses to data/raw/{mode}/ and normalized JSON to data/

set script_dir (status dirname)
set data_dir $script_dir/../data
set raw_dir $data_dir/raw
mkdir -p $data_dir $raw_dir

set -l strip_width 10
set -l max_retries 3
set -l retry_delay 3
set -l strip_delay 10

# Mode definitions: name followed by query body (bbox injected per strip)
# Names here match data file names and keys in index.html QUERY_MODES.
# User-facing labels (in index.html):
#   subway-nodes  → "Subways (strict)"   — exact station=subway nodes only
#   subway-all    → "Subways"            — nodes, ways, relations
#   subway-broad  → "Subways (broad)"    — includes alternate tagging
#   all-rail      → "All rail"           — adds light rail, monorail, tram
#   airports      → "Airports"           — aerodromes worldwide
set -l modes \
    'subway-nodes' 'node["station"="subway"];out body;' \
    'subway-all' 'nwr["station"="subway"];out body center;' \
    'subway-broad' '(nwr["station"="subway"];nwr["railway"~"station|halt"]["subway"="yes"];);out body center;' \
    'all-rail' '(nwr["station"="subway"];nwr["railway"="station"]["subway"="yes"];nwr["station"~"light_rail|monorail"];nwr["railway"~"tram_stop|halt"];);out body center;' \
    'airports' 'nwr["aeroway"="aerodrome"];out body center;'

set -l has_failures false

for i in (seq 1 2 (count $modes))
    set name $modes[$i]
    set query_body $modes[(math $i + 1)]
    set mode_raw_dir $raw_dir/$name
    set outfile $data_dir/$name.json

    mkdir -p $mode_raw_dir

    echo "=== Fetching $name in $strip_width° longitude strips ==="
    set -l strip_num 0
    set -l success_files
    set -l failed_strips

    for lon_start in (seq -180 $strip_width 170)
        set lon_end (math $lon_start + $strip_width)
        set strip_num (math $strip_num + 1)
        set strip_file $mode_raw_dir/strip-(printf '%03d' $strip_num).json

        set query "[out:json][timeout:60][bbox:-90,$lon_start,90,$lon_end];$query_body"

        echo -n "  [$strip_num/36] lon $lon_start to $lon_end... "

        # Skip if already downloaded and valid
        if test -f $strip_file; and jq -e '.elements' $strip_file >/dev/null 2>&1
            set count (jq '.elements | length' $strip_file)
            echo "$count elements (cached)"
            set -a success_files $strip_file
            continue
        end

        set -l success false
        for attempt in (seq 1 $max_retries)
            if test $attempt -gt 1
                echo -n "retry $attempt... "
                sleep $retry_delay
            end

            curl --max-time 120 \
                --data-urlencode "data=$query" \
                'https://overpass-api.de/api/interpreter' \
                -o $strip_file 2>/dev/null

            if test $status -ne 0
                continue
            end

            # Verify valid JSON with elements array
            jq -e '.elements' $strip_file >/dev/null 2>&1
            if test $status -eq 0
                set success true
                break
            end
        end

        if $success
            set count (jq '.elements | length' $strip_file)
            echo "$count elements"
            set -a success_files $strip_file
        else
            echo "FAILED after $max_retries attempts"
            set -a failed_strips "$lon_start to $lon_end"
            rm -f $strip_file
        end

        # Rate limit delay between requests
        if test $strip_num -lt 36
            sleep $strip_delay
        end
    end

    # Merge all strip files into combined raw response
    if test (count $success_files) -eq 0
        echo "  ERROR: no strips downloaded for $name"
        set has_failures true
        continue
    end

    echo "  Merging (count $success_files) strips..."
    jq -s '{elements: [.[].elements[]]}' $success_files >$mode_raw_dir/combined.json

    if test $status -ne 0
        echo "  ERROR: merge failed for $name"
        set has_failures true
        continue
    end

    # Normalize
    jq -f $script_dir/normalize.jq $mode_raw_dir/combined.json >$outfile

    if test $status -ne 0
        echo "  ERROR: normalize failed for $name"
        set has_failures true
        continue
    end

    set count (jq length $outfile)
    set size (ls -lh $outfile | awk '{print $5}')
    echo "  $name: $count stations, $size"

    if test (count $failed_strips) -gt 0
        echo "  WARNING: Failed strips: $failed_strips"
        set has_failures true
    end

    echo
end

if $has_failures
    echo "Done with errors. Rerun to retry failed strips."
    exit 1
else
    echo "Done."
end
