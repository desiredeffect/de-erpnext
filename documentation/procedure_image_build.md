# Basic Build Procedure
This is meant to be a quick order of operations / reference checklist - read the overview and image section below for explainers and context.

This sequence assumes you've already validated / run checks in a test-bed & are getting ready to set up an image for a site update. End state of this should be a new image visible when you run `docker images`.
1. Pull any updates from `de-erpnext` repository
2. Update / set up your `.env` file  - ensure you have:
	1. incremented the `DE_SITE_VERSION`
	2. set a valid / non-expired `PAT_DESIRED_EFFECT` github access token
	3. (especially if it's been a while) check that the schema of `.env` and `de-example.env` match)
3. Update / set up your `apps.json` - set your app branch identifiers to the release you're targeting.
4. Ensure your `build_command.sh` is set how you want (especially if you're changing Node or python environments, you might want to enable the `--no-cache` option)
5. Run `build_command.sh` watch the output of the process to make sure that things are proceeding correctly. If all goes well the process should take 2-4 minutes or so end-to-end (generally on the longer side of that range if you've enabled `--no-cache` or haven't run a build in this build environment before)
## Update Procedure

After you've gotten your new image, you'll need to spin-down your site and then spin up the new one
```bash
docker compose -p {project_name} -f {compose_file_name.yaml} down
# After waiting for the full shutdown process
docker compose -p {project_name} -f {compose_file_name.yaml} up
```
A couple of things to note about this process
1. `project_name` should be consistent over time - there isn't a real reason to ever change this
2. `compose_file_name` should generally remain consistent over time usually `compose-main.yaml` - but even if you're changing it it's critical to spin-down with the same compose you spun up with to be sure you caught all the containers. As such, especially if an update might change your compose file (especially service, volume or network designators), it might be worth making a temporary copy of your compose file before you pull updates just to ensure you're using exactly the same compose-file & aren't left with dangling containers.

> [!CAUTION]
> Don't shortcut this process. You really need to compose down on the containers because you need to destroy them. That way you start back up, you'll make new containers that used the new image in their construction.

As a final step, after having spun up our site again we need to run a migration to ensure any database schema updates have been done. You need to pull up a bash prompt inside the containers to run the command

```bash
docker exec -it {projectname-containername} /bin/bash
```

Once you're got your prompt pulled up, you'll need to run the migration command.

```bash
bench migrate
```

This process will update database schema to match doctype schema noted in your apps, it will also run any patches that haven't been run on the database before (sequentially). 

Note this is a bit of a finicky process, and failed patches can be problematic because they won't run again if the system already notes them as having run before. Quick and dirty bypass is to add a comment at the end of the line within `patches.txt` (because the system will note it as having).

# Overview 
In the context of Docker, a container is the actual program / object / instance with which we interact. It is meant to be a disposable object (i.e. not persistent between runtimes) and if proper docker principles are being followed, should be discardable without concern. 

Containers are built from docker images via commands provided either manually or through a docker compose script. Data persistence / more permanent storage is provided via volumes. Compose script configuration & volume manipulation are discussed in depth elsewhere in our documentation.

Images are the building blocks of a docker setup, acting as a read-only source of instructions, libraries, runtimes, dependencies, and environment settings for creating a container. 

Our ERPNext deployment consists of a custom image we build ourselves that we then use in conjunction with a customized compose script to create our live-site environment that facilitates database and inter-service interactions.

> [!NOTE]
> We're grossly simplifying what images are & do in docker here. Much more thorough & comprehensive documentation is available on the docker [architecture documentation](https://docs.docker.com/get-started/overview/#docker-architecture).
## Our Deployment "Constellation"

Our full deployment consists of 4 images, 5 persistent (and 8 anonymous / non-persistent) volumes, all linked to 13 (or more) containers. We'll quickly run through what all these are / do.
### Images:
1. **erpnext-custom -** this is our homemade image that will be our source of app updates. We'll be custom building this for updates
2. **redis -** used for our caching / queueing services
3. **mariadb -** used for our database management service
4. **traefik -** not a core dependency, but we're configured to use traefik as our reverse proxy service for routing.

> [!NOTE]
> If you're running a test-bench and intend to run UI testing, you'll also inevitably need the `cypress/included` image in order to run the Cypress UI testing suite
### Containers
#### Startup Containers
These are containers that will run at startup, then exit out once they've finished their job. They're used to ensure our environment is set up appropriately so everything else can start running.
1. **configurator -** a short lived container (the first to run); sets global config settings (stored in the `sites` volume in  `common_site_config.json`) for apps list, mariadb host/port, and redis cache + queue. Then exits out
2. **create-site -** attempts to set up a new site by the site-name set in our `.env file` - process is skipped if site already exists.
#### Core Containers
These are the core of our site service & will run as long as our site runs. All of these run off of our erpnext-custom image.
1. **backend -** a Werkzeug server; if you need to pop-in via command line for some on-the-fly bench commands, monitoring or config, this is where you'd do it
2. **frontend -** serves js/css assets & routes incoming requests. In our case configured to work with traefik as a reverse proxy. 
3. **websocket -** a Node server to run socketio (things like responsive live updates will rely on this)
4. **queues -** sets up bench workers to consume queued actions. Many actions in ERPNext are handled as enqueued tasks that are handled "when we can get to it". Note that we can dynamically scale up/down the number of queues we have at any time. This scaling can be scheduled if you expect regular periods of high activity. Default queues are:
	1. **queue-short -** can consume short & default queues
	2. **queue-long -** can consume any queue (short, default or long)
5. **scheduler -** python server to run cronjob / scheduled activities
#### Additional Services
These are additional services, broken out because they use different images and volumes.
1. **db -** our MariaDB server. Handles all database storage / handling tasks
3. **redis-queue** - runs our queue & socketio data services
4. **redis-cache -**  our database cache, afaik not strictly required, but great for acceleration
5. **traefik -** our reverse proxy service, used for routing
6. **restic -** this one is still on the fence, but this service would be used for backing up our site & db data
### Volumes
1. **sites -** `site` directory containing site configs, db credentials and public/private files
2. **db-data -** stores persistent MariaDB info / database
3. **logs -** `logs` directory containing our log files, useful for monitoring site health & troubleshooting
4. **redis-cache -** stores cached items to reduce how often you need to pull from the slower access db
5. **redis-queue -** stores our queue service data (which in turn gets consumed by our queue containers)
6. **anonymous volumes -** these are created when an image specifies a volume, but none is allocated / specified in the corresponding compose file using that image. In our case, this is our `sites/assets` folder which acts as a 
# Our Custom Docker Image
This image is used by all our core containers and contains app versions for all the apps we have installed on our site.
## Included Apps

|    App     | Current Version | Description                                                                                             |
| :--------: | :-------------: | ------------------------------------------------------------------------------------------------------- |
|   Frappe   |     15.17.3     | core framework for webserver, ORM handling & services                                                   |
|  ERPNext   |     15.17.0     | core business functionality and ERP doctype systems                                                     |
|    HRMS    |     15.13.1     | HR functionality - usage will be expanded later                                                         |
|  Payments  |      0.0.1      | Used for stripe payment integration                                                                     |
|  de_macrs  |      0.0.4      | contains MACRS functionality (macrs depreciation, 179 depreciation)                                     |
| de_customs |      0.0.5      | contains modules for other DesiredEffect specific modules (such as custom workflows, API handling, etc) |
## Build Process

We build our custom image ourselves via a build script in our de-erpnext development environment. The build process is detailed below

Our basic build command is run via navigating to our workspace directory & running the build script (which is as simple as `./build_command.sh`). This is a simple script contains a default build command with basic arguments and a simple access token substitution (discussed below).

There are a few points of configurability / customization to note:

Our build script is dependent on two files (both of which are / need to be located in the same directory as our build script): a `.env` file and `apps.json`

> [!IMPORTANT] 
> **Lack of an Image Repo**
> As of now we do not have a dockerhub image repository. This being the case, it would be in all our best interests to keep a config log of app version numbers for each build (i.e. site v1.1.5 used erpnext v15.3.2, de_macrs v0.4.3...etc). This will make it much easier to walk back and build up a historical site image if needed.
> 
> A use case for this might be if an accountant needed to pull a version of the site & database from a year ago to see how something was entered, this would make that a 10 minute process max.
### Environment (.env) file
This file contains configuration data needed during the build (and spin-up) process. Critical fields for the .env file are noted below
- `DE_MACRS_PAT` - needs to contain a valid github PAT (personal access token) as we are accessing multiple private repositories during our image building process, and thus we need to inject this PAT into the build command. 
- `DE_SITE_VERSION` - Sets the version number with which our build image will be tagged

> [!IMPORTANT]
> The `.env` file is untracked by default, so you need to copy the `de-example.env` and fill in your desired configuration details

There are more critical environment variables, but these are the ones that matter for the purposes of image building. The other environment variables available in the `.env` file will be covered in the compose configuration doc.

> [!WARNING] 
> It's easy to forget to update your `DE_SITE_VERSION` - if you forget about this & build an image with the same tag as one you've previously built it's annoying but not unsalvageable. When docker detects you're about to build an image with the same tag as one it already has stored in the local environment, it just deallocates the tag from the old image and adds it to the new image as such you need to manually reallocate tags.
> ```bash 
> docker image tag {SOURCE_IMAGE}:[TAG] {TARGET_IMAGE}[:TAG]
> ``` 
> This means you just need to update the tags in your new image, and then look for your old untagged image & add back the appropriate tag. A more thorough discussion of how the tagging system works for images is available in the [docker docs](https://docs.docker.com/reference/cli/docker/image/tag/.

### Apps JSON
This is fairly simple - our apps JSON needs to include entries for all the apps we want to include in the image, and it also needs to have correct branch targeting

> [!TIP]
> `--branch` is something of a misnomer in this case. While it can be a literal branch, it can also be used to specify a release tag for that repository. In an effort to make sure that our image versions are highly specific and trackable in terms of app versions used (such that in the future we could rebuild an image if need be), we use release targets whenever possible
> > [!NOTE]
> > Payments specifically doesn't have an associated release tag because it does not appear that the development team for the Payments app is using releases (hence why the version of the app is still `0.0.1` even though the app has been under active development/updating for a few years)

### Build Script

There are a couple of tweakable options worth discussing in the build script
- `--build-arg` - we can set our frappe, python & node versions here. Unless we have a compelling reason to not do so, we should generally make these match the versions noted in our dockerfile
- `--no-cache` - There is a commented out "`--no-cache`" option that you can pull into your flags. By default docker generates build caches of items / libraries it has used for building. These are great as they reduce network traffic and needless re-downloading. But docker isn't always great at checking whether a library or app has updated. So if you're migrating app versions, or especially if you're migrating python or node versions it is **highly** recommended that you use this flag.

```bash
# Run a replacement on the token title with SED & export as a base64 var_  
json_contents=$(cat ./apps.json)  
json_contents=$(echo "$json_contents" | sed "s/\${DE_MACRS_PAT}/$DE_MACRS_PAT/g")  
export_ APPS_JSON_BASE64=$(echo $json_contents | base64 -w 0)

docker build \  
  --build-arg=FRAPPE_PATH=[https://github.com/frappe/frappe](https://github.com/frappe/frappe) \  
  --build-arg=FRAPPE_BRANCH=version-15 \  
  --build-arg=PYTHON_VERSION=3.11.6 \  
  --build-arg=NODE_VERSION=18.18.2 \  
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \  
  --tag=desiredeffect/erpnext-custom:$DE_SITE_VERSION \  
  --file=images/custom/Containerfile .

  #--no-cache\
```

The actual build process is fairly "set & forget". Just set your configs in your `apps.json`, `.env` and `build_command.sh` the way you want them and let it run. The process will take a few minutes, especially if you're using the `--no-cache` option.

> [!CAUTION] 
> If you're doing multiple image builds, and especially if you're doing many of them without caching, you'll end up with a bunch of very well hidden build cache artifacts that aren't doing you any good. As such it's good practice to periodically run `docker builder prune`. This won't destroy anything in active use. But it can mean increased network utilization when you're making a new build. In general the benefits of avoiding cached data issues outweigh this increased use

When your build process is complete, you should have an image containing everything needed to spin up our erp site.