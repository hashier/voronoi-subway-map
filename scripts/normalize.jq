# Extract lat/lon/name, filter nulls, deduplicate exact coordinates
.elements
| map({lat: (.lat // .center.lat), lon: (.lon // .center.lon), name: .tags.name})
| map(select(.lat != null and .lon != null))
| unique_by([.lat, .lon])

# Merge nearby stations with the same name (~200m = 0.002 degrees)
# Group by name + rounded coordinates, average each cluster
| group_by([.name, (.lat * 500 | round), (.lon * 500 | round)])
| map({
    lat: (map(.lat) | add / length),
    lon: (map(.lon) | add / length),
    name: .[0].name
  })
| sort_by([.lat, .lon])