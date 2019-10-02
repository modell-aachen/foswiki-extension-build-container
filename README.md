# Foswiki Extension Build Container

## Building

Copy the `example.env` to `.env` and set `GITHUB_ORGANIZATION`

After that run
```
./build.sh --help
```
 to gather more information.

## Examples

```
./build.sh --docker-image
```

Only build the docker image

```
./build.sh -o /opt/build/
```

Build the specified repo (from `.env` file) and deploy it to `/opt/build`

```
./build.sh -c 8 -l
```

Build local specified repo (from `.env` file) with 8 cores

