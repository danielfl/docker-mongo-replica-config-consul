#!/bin/bash

declare -a endpoints
master=""

for endpoint in $(dig +short SRV ${CONSUL_SERVICE_NAME}.service.consul | awk '{print $4":"$3}'); do
    hostname=$(echo $endpoint | cut -d ':' -f 1)
    port=$(echo $endpoint | cut -d ':' -f 2)

    hostname=$(dig +short $hostname)
    if [[ $hostname != "" ]]; then
        if [[ "${endpoints[@]}" == "" ]]; then
            endpoints=("$hostname:$port")
        else
            endpoints=("${endpoints[@]}" "$hostname:$port")
        fi
    fi
done

if [ ${#endpoints[@]} -eq 0 ]; then
    echo "No endpoints registered in consul" >&2
    exit 1
fi

echo "Endpoints reported at ${endpoints[@]}" >&2

for endpoint in ${endpoints[@]}; do
    if (mongo --host $endpoint --eval 'db.isMaster().ismaster' | grep true) >> /dev/null; then
        master=$endpoint
        break;
    fi
done

if [[ $master == "" ]]; then
    if [ ${#endpoints[@]} -lt 3 ]; then
        echo "No current master and fewer than 3 nodes. Aborting rs initiate attempt" >&2
        exit 1
    fi

    echo "No current master found. Choosing 1st endpoint" >&2
    master=${endpoints[0]}

    mongo --host $master --eval "rs.status().code === 94 && rs.initiate()" >> /dev/null
    while (mongo --host $master --eval "rs.status().ok == 1" | grep 'false') >> /dev/null; do
        sleep 1
    done
fi
echo "Master is $master" >&2

# fix address of 1st host
echo "Fixing address of 1st host if needed" >&2
mongo --host $master --eval "var chars = rs.conf().members[0].host.match(/[a-zA-Z]/); if (chars && chars.length) { var conf=rs.conf(); conf.members[0].host = '${master}'; rs.reconfig(conf); }" >> /dev/null

for endpoint in ${endpoints[@]}; do
    if [[ "$endpoint" == "$master" ]]; then
        continue
    fi
    echo "Adding rs member $endpoint";
    mongo --host $master --eval "if (rs.conf().members.map(function(m) { return m.host; }).indexOf('${endpoint}') === -1) { rs.add('${endpoint}'); }" >> /dev/null
done

