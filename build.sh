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
            "        --cke          build local CKEditorPlugin\n" \
            "    -h, --help         shows this help message\n"
        printf "$text"
    }


    export $(egrep -v '^#' .env | xargs)
    local image_name=foswiki-extension-build
    local use_local_cke=0

    OPTS=`getopt -o r:b:p:o:h --long cke,repo:,branch:,path:,output:,docker-image,help -- "$@"`
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
                eval local_repository=$2
                local docker_mount_local_repo="-v $local_repository:/repo"
                GITHUB_REPOSITORY=`basename $local_repository`
                shift 2 ;;
            -o | --output )
                eval deploy_directory=$2
                shift 2 ;;
            --cke )
                use_local_cke=1
                shift ;;
            --docker-image )
                _build_docker_image $image_name
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

    if [ "$use_local_cke" = 1 ] ; then
        local userbinding="-u `id -u $USER`:`id -g $USER`"
        export HAS_LOCAL_CKE=1
    fi

    # reset built-in SECONDS function
    SECONDS=0

    docker run -it \
        -v ${deploy_directory}:/deploy \
        $userbinding \
        $docker_mount_local_repo \
        -e GITHUB_REF \
        -e GITHUB_REPOSITORY \
        -e HAS_LOCAL_REPOSITORY \
        -e HAS_LOCAL_CKE \
        $image_name

    duration=$SECONDS
    printf "\e[1;31mTime:     %d:%02d\e[0m\n" "$(($duration / 60))" "$(($duration % 60))"
}

_build_docker_image() {
    local image_name=$1
    docker build -t $image_name .
}

build-extension $@
