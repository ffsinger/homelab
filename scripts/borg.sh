#!/bin/bash

export BORG_REPO=/data/backups/borg
export BORG_PASSCOMMAND="cat /opt/borg/passphrase"

sudo -E borg "$@"
