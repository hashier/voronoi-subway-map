# Extract lat/lon/name, filter nulls, deduplicate exact coordinates
.elements
| map({lat: (.lat // .center.lat), lon: (.lon // .center.lon), name: .tags.name})
| map(select(.lat != null and .lon != null))
| unique_by([.lat, .lon])

# Merge same-name stations within 500m using actual distance
# 0.0045 degrees ≈ 500m (rough equirectangular approximation)
| group_by(.name)
| map(
    # Within each name group, cluster by proximity
    reduce .[] as $s ([];
      # Find first existing cluster within 500m
      (map(select(
        ((.lat - $s.lat) * (.lat - $s.lat) + (.lon - $s.lon) * (.lon - $s.lon)) | sqrt < 0.0045
      )) | first // null) as $match
      | if $match then
          # Merge into existing cluster (running average)
          map(if . == $match then {
            lat: ((.lat * .n + $s.lat) / (.n + 1)),
            lon: ((.lon * .n + $s.lon) / (.n + 1)),
            name: .name,
            n: (.n + 1)
          } else . end)
        else
          . + [$s + {n: 1}]
        end
    )
    | map({lat, lon, name})
  )
| flatten
| sort_by([.lat, .lon])