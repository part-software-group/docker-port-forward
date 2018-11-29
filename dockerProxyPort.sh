#!/usr/bin/env bash

function _version()
{
    echo "0.1.0"
    exit
}

function _usage()
{
    echo -e "Run docker for access port in container\n"
	echo -e "Usage:"
	echo -e "  bash $0 [OPTIONS...] CONTAINER\n"
	echo -e "Options:"
	echo -e "  -p, --port=<public-port>:<private-port>\tPort for connect to node application"
	echo -e "  \t\t\t\t\t\tExample: -p 5858-5860:5858-5860 -p 9229:3229"
	echo -e "  -v, --version\t\t\t\t\tShow version information and exit"
	echo -e "  -h, --help\t\t\t\t\tShow help options"
	echo ""

	echo -e "Examples:"
	echo -e "> bash $0 -p 5858:35858 container-name"
	echo -e "> bash $0 -p 5858-5860:35858-35860 container-name"
	echo -e "> bash $0 -p 5858-5860:35858-35860 -p 9229:3229 container-name"

    exit
}

### Detect script parameters
###################################################

declare -a PORT

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"

    case ${key} in
        # Container name
        ################
        -c|--container)
        CONTAINER="$2"
        shift
        shift
        ;;
        --container=*)
        CONTAINER="${key#*=}"
        shift
        ;;
        # Proxy port number (Node js container proxy port)
        ##################################################
        -p|--port)
        PORT+=("$2")
        shift
        shift
        ;;
        --port=*)
        PORT+=("${key#*=}")
        shift
        ;;
        # Other options
        ###############
        -v|--version)
        _version
        shift
        ;;
        -h|--help)
        _usage
        shift
        ;;
        *)
        POSITIONAL+=("$1")
        shift
        ;;
    esac
done
set -- "${POSITIONAL[@]}"

if [[ ${#POSITIONAL[@]} -eq 0 ]]; then
    _usage
fi

CONTAINER=${POSITIONAL[0]}

if [[ -z ${CONTAINER} ]]; then
    echo "[ERR] Container name is required!"
	exit 1
fi

if [[ -z ${PORT[@]} ]]; then
    echo "[ERR] Proxy port must be set!"
	exit 1
fi

docker inspect ${CONTAINER} >> /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "[ERR] Container name \"${CONTAINER}\" not exist!"
	exit 1
fi

trap removeContainer EXIT HUP INT QUIT PIPE TERM

function removeContainer() {
    docker rm -fv ${CONTAINER}-private-proxy >> /dev/null 2>&1
    docker rm -fv ${CONTAINER}-public-proxy >> /dev/null 2>&1
}

declare -i defaultPort=4848
declare -a accessPort
declare dockerPort

declare -a privateClientPort
declare -a privateDockerPort

declare -a publicClientPort
declare -a publicDockerPort

declare -a publicProxyPort

for i in ${PORT[@]}; do
    IFS=':' read -ra accessPort <<< "${i}"

    IFS='-' read -ra privateClientPort <<< "${accessPort[1]}"
    IFS='-' read -ra publicClientPort <<< "${accessPort[0]}"

    dockerPort+="-p ${accessPort[0]}:${accessPort[0]} "

    if [[ ${#privateClientPort[@]} -ne ${#publicClientPort[@]} ]]; then
        echo "Fail port forwarding! Public and private proxy port index not equal"
        exit 1
    fi

    if [[ ${#privateClientPort[@]} -eq 2 ]]; then
        for j in $(seq 0 $((${privateClientPort[1]} - ${privateClientPort[0]}))); do
            publicProxyPort+=(`expr ${publicClientPort[0]} + ${j}`)

            privateDockerPort+=(${defaultPort} `expr ${privateClientPort[0]} + ${j}`)
            publicDockerPort+=(`expr ${publicClientPort[0]} + ${j}` ${defaultPort})

            defaultPort=$((defaultPort + 1))
        done
    else
        publicProxyPort+=(${publicClientPort[0]})

        privateDockerPort+=(${defaultPort} ${privateClientPort[0]})
        publicDockerPort+=(${publicClientPort[0]} ${defaultPort})

        defaultPort=$((defaultPort + 1))
    fi
done

removeContainer

docker run -d -i --name ${CONTAINER}-private-proxy --network container:${CONTAINER} docker.loc:5000/socat:1.0.3-alpine /bin/sh >> /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    removeContainer

    echo "[ERR] Can't create container \"${CONTAINER}-private-proxy\""
    exit 1
fi

docker run -d -i --name ${CONTAINER}-public-proxy ${dockerPort}docker.loc:5000/socat:1.0.3-alpine /bin/sh >> /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    removeContainer

    echo "[ERR] Can't create container \"${CONTAINER}-public-proxy\""
    exit 1
fi

ip=`docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${CONTAINER}`
network=`docker inspect --format='{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' ${CONTAINER}`

function bindContainer() {
    sleep 6

    docker network disconnect ${2} ${CONTAINER}-public-proxy >> /dev/null 2>&1
    docker network connect ${2} ${CONTAINER}-public-proxy >> /dev/null 2>&1

    echo ${privateDockerPort[@]} | xargs -n 2 docker exec -d ${CONTAINER}-private-proxy /bin/sh -c 'socat TCP-LISTEN:$1,fork TCP:127.0.0.1:$2' argv0
    echo ${publicDockerPort[@]} | xargs -n 2 docker exec -d ${CONTAINER}-public-proxy /bin/sh -c 'socat TCP-LISTEN:$1,fork TCP:'${1}':$2' argv0

    echo "[INFO] Ready to access with public port(s): ${publicProxyPort[@]}"
    echo "Processing container event..."
}

bindContainer ${ip} ${network}

docker events --filter "container=${CONTAINER}" --filter "event=restart" --format "{{.ID}}" | while read container_id

do
    name=`docker inspect --format='{{.Name}}' ${container_id}`

    if [[ ! ${name:1} = ${CONTAINER} ]]; then
        continue
    fi

    docker restart ${CONTAINER}-private-proxy >> /dev/null 2>&1
    docker restart ${CONTAINER}-public-proxy >> /dev/null 2>&1

    ip=`docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${CONTAINER}`
    network=`docker inspect --format='{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' ${CONTAINER}`

    bindContainer ${ip} ${network}
done