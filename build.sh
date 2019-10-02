#!/bin/bash

build-extension() {

    usage() {
        printf -v text "%s" \
            "build.sh <extension repo> [OPTION...]\n" \
            "    -l, --local        use local repository\n" \
            "    -b, --branch       branch to build repo. If not specified, .env is used\n" \
            "    -o, --output       deploy directory\n" \
            "    -c, --cores        number of cpu cores\n" \
            "        --docker-image builds the docker image\n" \
            "        --cke          build local CKEditorPlugin\n" \
            "    -h, --help         shows this help message\n"
        printf "$text"
    }


    export $(egrep -v '^#' .env | xargs)
    export CORES=3
    local deploy_directory=$REPOS_DIRECTORY/deploy
    local image_name=foswiki-extension-build

    OPTS=`getopt -o c:lb:o:h --long cores:,local,cke,branch:,output:,docker-image,help -- "$@"`
    if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

    eval set -- "$OPTS"

    while true; do
        case "$1" in
            -b | --branch )
                GITHUB_REF=$2
                shift 2 ;;
            -l | --local )
                export HAS_LOCAL_REPOSITORY=1
                shift ;;
            -o | --output )
                eval deploy_directory=$2
                shift 2 ;;
            -c | --cores )
                CORES=$2
                shift 2 ;;
            --cke )
                export HAS_LOCAL_CKE=1
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

    shift $(expr $OPTIND - 1 )
    if [ "$1" ]; then GITHUB_REPOSITORY=$1; fi

    if [ "$HAS_LOCAL_REPOSITORY" = 1 ] ; then
        local docker_mount_local_repo="-v $REPOS_DIRECTORY/$GITHUB_REPOSITORY:/repo"
    fi

    if [ ! -d "$deploy_directory" ] ; then
        mkdir "$deploy_directory"
        chmod 777 -R "$deploy_directory"
    fi

    if [ "$HAS_LOCAL_CKE" = 1 ] ; then
        local userbinding="-u `id -u $USER`:`id -g $USER`"
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
        -e CORES \
        --rm \
        $image_name

    duration=$SECONDS
    printf "\e[1;31mTime:     %d:%02d\e[0m\n" "$(($duration / 60))" "$(($duration % 60))"
}

_build_docker_image() {
    local image_name=$1
    docker build -t $image_name .
}

build-extension $@
