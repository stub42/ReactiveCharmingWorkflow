# Reactive Charming Workflow

An opinionated guide by stub.

Feedback welcome. If you learn something here, great. If I learn something
here, even better.


## Basic Filesystem Layout

The recommended basic directory structure separates layers, interfaces
and generated charms. Identify these directories using environment variables:

```sh
export CHARM_ROOT=$HOME/charms
export LAYER_PATH=$CHARM_ROOT/layers
export INTERFACE_PATH=$CHARM_ROOT/interfaces
export JUJU_REPOSITORY=$CHARM_ROOT/repo
```

Make sure the directories all exist. `LAYER_PATH` and `INTERFACE_PATH` are
used by charm-tools when generating a charm. They will contain branches
of the layers and interfaces you are working on or have decided to pin:

```sh
mkdir -p $LAYER_PATH $INTERFACE_PATH
```

`JUJU_REPOSITORY` is used by Juju 1.x to locate charms stored locally,
and charm-tools defaults to building charms into this tree too.
Using a couple of symbolic links we can create a development environment
that works with both Juju 1.x and Juju 2.x, and where charm-tools builds
charms into a consistent location:

```sh
ln -sf $JUJU_REPOSITORY $JUJU_REPOSITORY/trusty
ln -sf $JUJU_REPOSITORY $JUJU_REPOSITORY/xenial
ln -sf $JUJU_REPOSITORY $JUJU_REPOSITORY/builds
```


## Layers and Interfaces with Git

In the Reactive Framework, your charm is generated from a layer
(which I call the primary layer). A charms primary layer is no different
to other layers, and could be used as a dependency to a different primary
layer to generate a different charm, so I store them all together
in `LAYER_PATH`. Interface layers do not share the same namespace, so
are stored separately in `INTERFACE_PATH`.

In the following examples, I'll use the CNAME variable to represent
the charm name to make cut and paste and inclusion in Makefiles or scripts
easier:

```sh
export CNAME=example
```

To create a charm using the Reactive Framework, you need a primary layer.
Create a fresh one:

```sh
charm create -t reactive-python $CNAME $LAYER_PATH
cd $LAYER_PATH/$CNAME
git init
git add .
git commit -m 'Initial template'
```

This generated charm will need work to its `metadata.yaml` before it is in
a state the charmstore will accept (declare series, remove placeholder
relations).

Alternatively, you could clone an existing repository if you are working
on an existing charm:

```sh
cd $LAYER_PATH
git clone git+ssh://git.launchpad.net/postgresql-charm postgresql
```

The primary layer gets built into a charm using charm-tools. I build
into a separate branch in the same repository, preserving the history
of the built artifacts and dependencies. The easiest way of doing this
is to create a second working tree of the git repository.

```sh
cd $LAYER_PATH/$CNAME
git branch test-built master
git worktree add $JUJU_REPOSITORY/$CNAME test-built 
```

My branch is called `test-built`, and after testing it will be merged into
a final `built` branch. These correspond to the development and stable
charm store channels.

For lightweight, work in progress builds use `charm build` to regenerate
the charm from your primary layer and its dependencies:

```sh
cd $LAYER_PATH/$CNAME
charm build -f -o $JUJU_REPOSITORY -n $CNAME
```

:warning: Note that dependencies are pulled from `$LAYER_PATH` and
`$INTERFACE_PATH` if they exist, falling back to the branches registered at
http://interfaces.juju.solutions if they are not found there. Use
`charm build --no-local-layers` to override this behavior.

After committing changes to your master branch, you can generate and
commit a proper build, which takes a few steps:

1. Clean the build area of artifacts from WIP builds and cowboys:
   ```sh
   cd $JUJU_REPOSITORY/$CNAME
   git reset --hard test-built
   git clean -ffd
   ```
   
2. Merge the primary layer without committing. Our build will be linked
   to the source revision and share revision history:
   ```sh
   cd $JUJU_REPOSITORY/$CNAME
   git merge --log --no-commit -s ours -m "charm-build of master" master
   ```

3. Regenerate the charm:
   ```sh
   cd $LAYER_PATH/$CNAME
   git stash save --all
   charm build -f -o $JUJU_REPOSITORY -n $CNAME $LAYER_PATH/$CNAME
   git stash pop
   ```
   
4. Finalize the commit:
   ```sh
   cd $JUJU_REPOSITORY/$CNAME
   git add .
   git commit --no-edit
   ```

You now have a test-built branch of the generated charm containing all the
revision history, with every change traceable to a build or back to the
source change. This is your development release. Test it locally, or
publish it to the charm store for others to test. You can publish directly
from `$JUJU_REPOSITORY/$CNAME` if it is clean, or do it the following
way to guarantee only tracked files get uploaded and no secrets or messy
temporary artifacts:

```sh
cd $LAYER_PATH/$CNAME
git clone -b test-built . tmp-test-built
charm publish -c development `charm push tmp-test-built $CNAME 2>&1 \
    | tee /dev/tty | grep url: | cut -f 2 -d ' '`
rm -rf tmp-test-built
```

(Please excuse the ugly shell command; charm-tools does not yet support
the common case of publishing what you just pushed without cut and paste)

Once testing is over, you can publish your stable branch. I keep the
tested releases on the built branch, with each revision corresponding
to a stable release in the charm store. We tag the released revision with
the charm store revision so we can easily match deployed units with
the code they are running:

```sh
    cd $LAYER_PATH/$CNAME
    git branch built test-built
    git clone --no-single-branch -b built . tmp-built
    cd tmp-built
    git merge --no-ff origin/test-built --log --no-edit
    export _built_rev=`charm push . $CNAME 2>&1 \
        | tee /dev/tty | grep url: | cut -f 2 -d ' '`
    git tag `echo $_built_rev | tr -s '~:/' -`
    git push --tags .. built
    charm publish -c stable $_built_rev
    cd ..
    rm -rf tmp-built
```

=== Makefile ===

The above guides can be converted to Makefile rules:

https://github.com/stub42/ReactiveCharmingWorkflow/blob/master/Makefile

=== Future ===

After documenting the above processes, it becomes apparent that charm-tools,
charms.reactive and git still don't mesh well. From a developer perspective,
it is far too complex to say 'publish this branch'. With charms.reactive,
a charm is now akin to a binary package and must first be built. charm-tools
does not help, as it chose to be tool agnostic so you are stuck juggling
all the VCS details yourself. I think a more opinionated tool would be
much more transparent, providing charmers with the scafolding they need and
being much easier to integrate with CI systems for testing and final
publication. I think that git plugins would provide the best UI.

- [ ] `git charm build [--log] [-m msg] [branch]`

    - charm-build to the destination branch
    - what to do with uncommitted changes? We could use stash
      to create a commit to track the changes, or we could refuse to run,
      or just not worry about it and let the dev decide (maybe a -f or
      --uncommitted)
    - Maybe instead of building to a branch, we just build a tagged revision.
      This would work the same, except the build revision would have a single
      parent (the source branch) rather than two parents (the source branch
      and the previous build).
        - Fits nicer if you are creating builds from multiple source branches,
          or multiple builds from the same source revision (eg. deps updated)

- [ ] `git charm push [--resource RES ...] [branch] [CSURI]`
- [ ] `git charm publish -c [channel] [branch] [CSURI]`

    - Really, these should be the same command where publishing occurs if
      a channel is specified. But the charm-tools commands we need to wrap
      seem to have some differences in how resources are handled.

- [ ] `git charm layers`
    - `git charm layers fetch`
    - `git charm layers update [layer]`
    - Layers are mostly in git. We could embed them as git subtrees.
    - Solves the version pinning problem
    - Lets you hack on a layer in your local tree and push changes upstream.
    - Fallback to existing `LAYER_PATH` and `INTERFACE_PATH` if a non-git
      repo is in play.
