This is a quick & dirty method to do small tweaks to sever-side code on a site while its deployed & live. The primary use case for this is to bypass or modify behavior that's causing site breakage. It should be considered a temporary band-aid, and should be followed up by a proper patch at earliest convenience.
# Process
## TLDR version
1. Get onto the server (via `ssh`)
2. Enter your container (via `docker compose -f {compose-file}.yaml exec -it {service-name} /bin/bash`)
3. Modify your code / module (via `vim`)
4. delete pycaches (`rm` the `.pyc` file in `{module location}/__pycache__`  with same name as your module)
5. restart container (via `docker compose -f {compose-file}.yaml restart {service-name}`)
## Detailed explainer
### Step 1 - Get into the server
First we need to get into a terminal on our server. This is going to involve a couple of steps
1. **SSH in -** this requires ssh credentials configured for the server.
2. **Navigate to Site Config -** this is where the repository for our project is located. This will looks something like `/srv/git/{project-name}` (currently `/srv/git/test-erpnext`)
### Step 2 - Enter your subject container
Our frappe deployment contains a dozen or more containers. To move forward you need to know which container you have to target. There are only two likely targets for this process
1. **backend** - this is our Werkzeug server & handles most server operations, this is our likeliest candidate
2. **queue-{x}** - these are workers that "gobble up" enqueued actions (we currently have "short" and "long") that have been pushed onto the redis-managed queue. This might be your target if you're trying to tweak something that breaks on "mass" actions (like say deleting 50 documents). Note that the way our queue gobblers are configured, there's overlap on "short" and "default" queues. This makes which queue will carry out an action non-deterministic in some cases. As such, you'll need to carry out the rest of the procedure for any possible queue services. (If you don't know, change each of them).

> [!IMPORTANT]
> Be aware each container is its own self-contained ecosystem. Any code tweaks you made to one container doesn't propagate to others.

You'll enter your container using a docker command that includes the compose command as a target
```bash
docker compose -f {compose-file}.yaml exec -it {service-name} /bin/bash
```

Example for our current setup
```bash
docker compose -f compose-main.yaml exec -it backend /bin/bash
```

This should get you to a bash terminal session inside your container.
### Step 3 - Modify your code
Vim is burned into the image, so just use that. Only thing to be aware of is that frappe's convention is to use tabs instead of spaces for indents. As such, make sure you to enable `: set noexpandtab` in your vim instance.

If we don't have a cache to reckon with, we're done here & can `exit` out and go.
### Step 4 - Delete pycache (POSSIBLY NOT REQUIRED)
From your modified modules directory, enter the local `__pycache__` directory (if you can't find one, you're done). Find the `.pyc` file that shares a name with your modified module. Delete it. Then `exit` out of the container & back into your remote server terminal session.
### Step 5 - Restart container
Restart the container using our compose script to ensure the same configs are set.
```bash
docker compose -f {compose_file}.yaml restart {service-name}
```

Example for our current setup
```bash
docker compose -f compose-main.yaml restart backend
```
# Warnings / Limitations
This is a quick & dirty way to very very quickly fix a minor issue. It's meant to be a band-aid to get you through till you can fix it properly. The changes you make with live only on the container, so it won't persist past a "docker down -> docker up" or anything else that would rebuild the container. So when you do this, you really should fix the problem properly ASAP by way of :
1. Updating your app and making a new release
2. building a new site image with that release
3. pulling the site down, configuring to the new image & going back up
# Explanation / Architecture
Python is an interpreted language - this naturally leads to a big performance hit relative to compiled languages because of the parsing process to turn the human readable python into more machine-friendly instructions. Python attempts to mitigate this by generating an intermediate "bytecode"

> [!NOTE]
> Python will never be a "fast" or efficient language. Depending on the task, python might take [1-2 orders of magnitude](https://levelup.gitconnected.com/how-slow-is-python-6f2fc1fbfbaa) more resources (time, memory, energy) than a more efficiency minded language. 
> 
> That's ok! Python trades that efficiency for flexibility & utility. And that performance hit isn't the end of the world in a space where you might have to wait multiple milliseconds to get a response from another service. Just be aware you're driving a dump truck, not a ferrari  

Normally when code changes, the interpreter updates the pycache the next time that module is imported. Now the problem here is that Gunicorn (the backend handler for server actions) appears to make a persistent worker & as a result the bytecode does not get regenerated because the module gets loaded, then stays loaded.

As such, we need to restart the backend container after you've updated your code in order to ensure that the cache gets reloaded and thus regenerated
