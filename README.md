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

/!\ Note that dependencies are pulled from `$LAYER_PATH` and `$INTERFACE_PATH`
if they exist, falling back to the branches registered at
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
   git merge --log --no-commit -s ours master
   ```

3. Regenerate the charm:
   ```sh
   charm build -f -o $JUJU_REPOSITORY -n $CNAME $LAYER_PATH/$CNAME
   ```
   
4. Finalize the commit:
   ```sh
   cd $JUJU_REPOSITORY/$CNAME
   git add .
   git commit -m 'charm-build of master'
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
    git merge --no-ff origin/test-built --log -m 'charm-build of master'
    export _built_rev=`charm push . $CNAME 2>&1 \
        | tee /dev/tty | grep url: | cut -f 2 -d ' '`
    git tag `echo $_built_rev | tr -s '~:/' -`
    git push --tags .. built
    charm publish -c stable $_built_rev
    cd ..
    rm -rf tmp-built
```
