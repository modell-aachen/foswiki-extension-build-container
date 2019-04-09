Building the container:
docker build -t foswiki-extension-build .

Running the container:
docker run -it -v ~/deploy:/deploy --env-file .env foswiki-extension-build

Running the container for development
yarn watch
docker run -it -v ~/deploy:/deploy -v ~/foswiki-extension-build-container:/usr/src --env-file .env foswiki-extension-build
