#!/bin/bash

set -e
environ=$1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

[ -d "$environ" ] || { >&2 echo "No directory found: {$environ}"; exit 1; }

# if lock file exists
if [ -e "$environ/rsync.lock" ] && kill -0 $(cat "$environ/rsync.lock"); then
    >&2 echo "Lock file already exists: {$environ/rsync.lock}"
    (exit 1)
fi

trap "rm -f $environ/rsync.lock; exit" INT TERM EXIT
echo $$ > $environ/rsync.lock

[ ! -f rsync.secret ] || export RSYNC_PASSWORD="$(cat rsync.secret)"

for subfolder in $environ/*/ ; do
    [ -d "$subfolder" ] || subfolder="$environ"
    [ -e "$subfolder/read_files.sh" ] || { >&2 echo "No file found: {$subfolder/read_files.sh}"; exit 1; }
    if [ ! -e "$subfolder/print_rsync_iso.sh" ] && [ ! -e "$subfolder/print_rsync_repo.sh" ]; then
        >&2 echo "Neither of files found: {$subfolder/print_rsync_iso.sh} nor {$subfolder/print_rsync_repo.sh}"
        exit 1
    fi

    [ -e "$subfolder/print_openqa.sh" ] || { >&2 echo "No file found: {$subfolder/print_openqa.sh}"; exit 1; }

    bash -e "$subfolder/read_files.sh"

    [ ! -e $subfolder/.run_last ] || [ ! -z "$(diff --brief $subfolder $subfolder/.run_last | grep '.lst')" ] || { >&2 echo "No changes found since last run, skipping {$subfolder}"; exit 0; }

    logdir=$subfolder/.run_$(date +%y%m%d_%H%M%S)
    mkdir $logdir

    [ ! -e "$subfolder/print_rsync_iso.sh" ] || bash -e "$subfolder/print_rsync_iso.sh" > $logdir/rsync_iso.cmd 2> >(tee $logdir/generate_rsync_iso.err)

    [ ! -e "$subfolder/print_rsync_repo.sh" ] || bash -e "$subfolder/print_rsync_repo.sh" > $logdir/rsync_repo.cmd 2> >(tee $logdir/generate_rsync_repo.err)

    # store state of files for eventual troubleshooting and avoid indefinite openqa retry
    cp $subfolder/*.lst $logdir/
    cp $subfolder/*.sh $logdir/

    # remove symbolic link if exists
    [ ! -L "$subfolder/.run_last" ] || rm "$subfolder/.run_last"
    ln -s -T "$(pwd)/$logdir" $subfolder/.run_last

    [ ! -e "$subfolder/print_openqa.sh" ] || bash -e "$subfolder/print_openqa.sh" 2>$logdir/generate_openqa.err > $logdir/openqa.cmd

    for f in {rsync_iso.cmd,rsync_repo.cmd,openqa.cmd}; do
        bash -x "$subfolder/.run_last/$f" > "$logdir/$f".log 2>&1
    done
    [ "$subfolder" != "$environ" ] || break
done

:
