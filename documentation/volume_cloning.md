As a tool for testing & site duplication, we've written a volume archiving tool to do quick & dirty duplication of volumes including metadata labels (or tags as Docker refers to them).

> [!NOTE]
> It's worth noting that there are alternate strategies for copying information from / to volumes as outlined below
> ### Strategy 1 - Copy Files between Volumes
> The most quick & dirty way to get information from one volume to another is just to mount multiple volumes and then use filesystem level `cp` command (or the [docker cp command](https://docs.docker.com/reference/cli/docker/container/cp/)) to copy data between volumes.  This has the advantage of being intuitive and targeted, giving you exactly what you want. The disadvantage is that it's a very slow & manual process and you're only getting exactly what you're specifying
> ### Strategy 2 - Volume Duplication
> This is a more complicated way of doing things, but more useful for our purposes. This process generally involves making a tarball or other archival format (generally compressed) version of the volume, then decompressing / reexpanding the volume in another (or indeed the same) environment

## How Backup / Restoration Works Normally

Anything we're doing through our script / utility can also be done manually. Below is an outline of how that works process works in theory. Skip if you just need to get to "how do I use the utility"
### Volume Backup

The basic way to backup a volume into a tarball would like the below.

```bash
# create a new container named dbstore
docker run -v /dbdata --name dbstore ubuntu /bin/bash

# launch a new container mounting both the dbstore's volume + a local host directory
# Then run a command that tars the contents of the dbdata volume into our mounted /backups directory
docker run --rm --volumes-from dbstore -v $(pwd):/backup ubuntu tar cvf /backup/backup.tar /dbdata
```

As an alternate, if you can target a particular volume, you can use a command like

> [!TIP] 
> ``` bash
> docker run --rm \
>       -v de-erpnext_db-data:/backup-volume \
>       -v "$(pwd)":/backup \
>       alpine \
>       tar -zcvf /backup/my-backup.tar.gz /backup-volume
> ```
> - `docker run --rm` starts a docker container with the `--rm` flag indicating it'll automatically be removed on exit
> - `-v de-erpnext_db-data:/backup-volume \` uses `-v` to create a volume mount and mounts `de-erpnext_db-data` into the container at the path `/backup-volume` 
> - `-v "$(pwd)":/backup \` create another mount point to mount our current working directory (`$(pwd)`) of our local machine into the container at the path `/backup`. This is where the backup will get saved
> - `alpine` specifies the docker image to use for the container. In this case we're using a lightweight and minimal linux distro
> - `tar -zcvf /backup/my-backup.tar.gz /backup-volume` a command executed inside the container. We use `tar` with the flags `-zcvf` to create a compressed tar ball named `my-backup.tar.gz` in the `/backup` director (our current working directory) and fills it with  the contents of the `/backup-volume` directory, which corresponds to our db volume in this case

### Volume Restoration

This gives us a nifty tarball that preserve directory structure and compacts our data down for us. Then when we want to restore the volume, we'd just run that process essentially in reverse.

```bash
# As an example, let's make a new container called dbstore2
docker run -v /dbdata --name dbstore2 ubuntu /bin/bash
# Then just untar the backup file into the new containers data volume
docker run --rm --volumes-from dbstore2 -v $(pwd):/backup ubuntu bash -c "cd /dbdata && tar xvf /backup/backup.tar --strip 1"
```

## Limitations of Standard Backup / Restore Solutions

A couple things to note about this process:
1. **the `--strip 1` flag -** the backup process ads a level of directory hierarchy to the data being unpacked. For our purposes keeping the same structure of the original is critical, so this flag peels back the top layer of the hierarchy, getting us to the structure we need.
2. **Doesn't play well with volumes created or used in `docker compose`** - Volumes in docker have an element called "labels" which are essentially metadata used by docker to signal handling and tracking for volumes. Examples include tags that note a volume as anonymous (in `compose v2`) allowing volumes-so-tagged to be targeted by the `docker volume prune` command.

When a docker volume is made via the compose process, it will automatically be generated with 3 labels
1. `com.docker.compose.project` - a label corresponding to the [project name](https://docs.docker.com/compose/project-name/) which can specified in various ways with an order of precedence
2. `com.docker.compose.version` - a label indicating what version of docker compose was used to create the volume
3. `com.docker.compose.volume` - a label corresponding to the actual volume name itself - note that the name of the volume follows the general pattern of "`{project_name}_{volume_name}`"

> [!WARNING]
> If you try to spin up a project with volumes that don't have matching labels to what compose expects by contexts of your yaml file, you'll get an error to the effect of `Volume already exists but was not created by Docker Compose`. This can be avoided by adding an external tag in your compose file under the volumes you're trying to reuse.
> ```yaml
> volumes:
> 	my_existing_volume_name:
> 		external: true
> ```
> That being said, this seems like a poor practice to me and could allow for weird situations where bad / incorrect volumes are used unknowingly. As such, I feel like a better practice is to just make sure our volumes have correct labelling.

Now we can manually do volume creation while adding labels like so:

```bash
docker volume inspect proj1_vol1  # Look at labels of old volume - assume the labels below are what we saw

docker volume create \
           --label com.docker.compose.project=proj2 \
           --label com.docker.compose.version=2.2.1 \
           --label com.docker.compose.volume=vol2 \
           proj2_vol2
```

So putting what we've already got together, you CAN backup a volume taking note of the labels, then make a new volume while manually adding the labels, then restore into that newly labelled volume. But that's a super manual process that's a serious pain. Instead we wrote a utility to help that backup / restore process

## Tool Usage

The backup / restore should be a 1 command process
### Volume Backup Utility
Backup utility located at `tools/volume-restorer/volume-archive.sh`

The usage for the script is extremely simple:

```bash
./volume_backup {volume_name}
```

All you have to is target a valid volume & the script will do the rest, generating a compressed tarball that also includes special JSON file containing volume labelling information, titled `{volume_name}_volume_info.json`. This file will be read from by the restore script to restore volume labels.

Notes:
- Volume needs to actually needs to exist. As such, you should use `docker volume ls` to ensure that you're targeting an existent 
- The backup is made to a directory labeled "`./backup_{year_month_day}`" relative to your current working directory

### Volume Restoration Utility

Restore utility located at `tools/volume-restorer/volum-restore.sh`

The usage for the restore script is also extremely simple:

``` bash
sudo ./volume_restore {tarball_file} {optional_project_override}
```

In this case you'll note that there's an optional argument to override the project name. This is important as it allows you to "duplicate in place", creating a backup set of volumes for a project to allow for testing, etc.

Notes:
- the tarball being targeted needs to have been created via the `volume_backup` utility. If not, the archive won't have the volume metadata file and we won't be able to appropriately create a volume
- `sudo` is required for this command in order to allow us to preserve ownership when extracting from archives
## Resources: 

Below are useful resource for additional info / context related to docker volumes

- [Docker Docs - Volumes](https://docs.docker.com/storage/volumes/) - includes basic theory and commands around how volumes function
- [Docker Docs - Compose File (07-volumes)](https://docs.docker.com/compose/compose-file/07-volumes/) - provides syntax and options for how to define volumes within a compose file
- [Stack Overflow - Copying Docker Volumes](https://stackoverflow.com/questions/67567986/copy-docker-volumes) - a really useful thread discussing considerations for cloning docker volumes
- [Reddit -r/docker - docker in production](https://www.reddit.com/r/docker/comments/ckxj7e/docker_in_production_image_or_volume/) - a useful reddit thread about how to think about the role of volumes & images in a production pipeline.