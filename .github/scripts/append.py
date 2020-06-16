import json
import os
import sys

with open(sys.argv[1], 'r') as j:
    json_data = json.load(j)
    json_data.insert(0, sys.argv[2])

with open(sys.argv[1], 'w') as j:
    json.dump(json_data, j, indent=3)