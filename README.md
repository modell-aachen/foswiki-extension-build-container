# Foswiki Extension Build Container
### Building the container:
```bash
docker build -t foswiki-extension-build .
```

### Running the container:
```bash
docker run -it -v ~/deploy:/deploy --env-file .env foswiki-extension-build
```

### Running the container for development
```bash
yarn watch
docker run -it -v ~/deploy:/deploy -v ~/foswiki-extension-build-container:/usr/src --env-file .env foswiki-extension-build
```