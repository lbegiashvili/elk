#!/usr/bin/env bash

set -eu
set -o pipefail


source "${BASH_SOURCE[0]%/*}"/lib/testing.sh


cid_es="$(container_id elasticsearch)"
cid_mb="$(container_id filebeat)"

ip_es="$(service_ip elasticsearch)"
ip_mb="$(service_ip filebeat)"

grouplog 'Wait for readiness of Elasticsearch'
poll_ready "$cid_es" "http://${ip_es}:9200/" -u 'elastic:testpasswd'
endgroup

grouplog 'Wait for readiness of Filebeat'
poll_ready "$cid_mb" "http://${ip_mb}:5066/?pretty"
endgroup

# We expect to find log entries for the 'elasticsearch' Compose service using
# the following query:
#
#   agent.type:"filebeat"
#   AND input.type:"container"
#   AND container.name:"docker-elk-elasticsearch-1"
#
log 'Searching documents generated by Filebeat'

declare response
declare -i count

declare -i was_retried=0

# retry for max 60s (30*2s)
for _ in $(seq 1 30); do
	response="$(curl "http://${ip_es}:9200/filebeat-*/_search?q=agent.type:%22filebeat%22%&pretty" -s -u elastic:testpasswd)"

	set +u  # prevent "unbound variable" if assigned value is not an integer
	count="$(jq -rn --argjson data "${response}" '$data.hits.total.value')"
	set -u

	if (( count > 0 )); then
		break
	fi

	was_retried=1
	echo -n 'x' >&2
	sleep 2
done
if ((was_retried)); then
	# flush stderr, important in non-interactive environments (CI)
	echo >&2
fi

echo "$response"
if (( count == 0 )); then
	echo 'Expected at least 1 document'
	exit 1
fi
