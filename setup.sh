#! /bin/bash

usage()
{
  cat <<-EOF 1>&2
        use: setup.sh [OPTIONS]*
          Options:         Default 
            --host=HOST    localhost         
            --port=PORT    9999
            --user=USE     admin
            --pass=PAS     admin
            --dir=DIR      current dir
            --group=GROUP  Default
EOF
  exit 1
}



HOST=localhost
PORT=9999
USER=admin
PASS=admin
DIR="$PWD/${1#./}"
GROUP="Default"

while [ $# != 0 ]; do
  case "$1" in
    --host=*)
        HOST=$(echo $1 | sed 's%--host=%%')
        shift;;
    --port=*)
        PORT=$(echo $1 | sed 's%--port=%%')
        shift;;
    --dir=*)
        DIR=$(echo $1 | sed 's%--dir=%%')
        shift;;
    --user=*)
        USER=$(echo $1 | sed 's%--user=%%')
        shift;;
    --pass=*)
        PASS=$(echo $1 | sed 's%--pass=%%')
        shift;;
    --group=*)
        GROUP=$(echo $1 | sed 's%--group=%%')
        shift;;
    -?)
        usage
        ;;
    *)
        echo "Bad option - $1"
        usage
       ;;
 esac
done

CURL="curl --anyauth --user ${USER}:${PASS} -s -S"



$CURL -X POST -d @- -H "Content-type: application/json" \
  "http://${HOST}:8002/manage/v2/servers" <<-EOF
        { "server-name": "${PORT}-queryplan-viewer",
          "server-type": "http",
          "group-name": "$GROUP",
          "root": "${DIR}",
          "port": $PORT,
          "content-database": "Documents",
          "threads": 32,
          "error-handler" : "/MarkLogic/rest-api/error-handler.xqy"
        }
EOF

