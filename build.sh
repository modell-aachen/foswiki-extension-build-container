#!/bin/bash

build-extension() {

    usage() {
        printf -v text "%s" \
            "build.sh [OPTION...]\n" \
            "    -r, --repo         repo from github repository. Token and user have to be set.\n" \
            "    -b, --branch       branch to build repo. If not specified, .env is used\n" \
            "    -p, --path         path to local repo. If set, github repo is ignored\n" \
            "    -o, --output       deploy directory\n" \
            "        --docker-image builds the docker image\n" \
            "    -h, --help         shows this help message\n"
        printf "$text"
    }


    export $(egrep -v '^#' .env | xargs)
    IMAGE_NAME=foswiki-extension-build

    OPTS=`getopt -o r:b:p:o:h --long repo:,branch:,path:,output:,docker-image,help -- "$@"`
    if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

    eval set -- "$OPTS"

    while true; do
        case "$1" in
            -r | --repo )
                GITHUB_REPOSITORY=$2
                shift 2 ;;
            -b | --branch )
                GITHUB_REF=$2
                shift 2 ;;
            -p | --path )
                export HAS_LOCAL_REPOSITORY=1
                eval LOCAL_REPOSITORY=$2
                DOCKER_MOUNT_LOCAL_REPO="-v $LOCAL_REPOSITORY:/repo"
                GITHUB_REPOSITORY=`basename $LOCAL_REPOSITORY`
                shift 2 ;;
            -o | --output )
                eval DEPLOY_DIRECTORY=$2
                shift 2 ;;
            --docker-image )
                _build_docker_image $IMAGE_NAME
                return;
                shift ;;
            -h | --help )
                usage
                return
                shift ;;
            -- )
                shift
                break ;;
            * )
                break ;;
        esac
    done


    docker run -it \
        -v ${DEPLOY_DIRECTORY}:/deploy \
        $DOCKER_MOUNT_LOCAL_REPO \
        -e GITHUB_REF \
        -e GITHUB_REPOSITORY \
        -e HAS_LOCAL_REPOSITORY \
        $IMAGE_NAME
}

_build_docker_image() {
    IMAGE_NAME=$1
    docker build -t $IMAGE_NAME .
}

build-extension $@
